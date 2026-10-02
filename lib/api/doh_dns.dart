import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'jp_log.dart';

/// DoH（DNS-over-HTTPS）解析，供 [HttpClient.connectionFactory] 在系统 DNS
/// 不可用（如 Clash TUN / fake-ip）时引导建连。
///
/// 引导端点优先使用 **IP 字面量**，避免解析 DoH 服务器时再次依赖系统 DNS。
///
/// 引导用 [HttpClient] 必须在 [HttpOverrides.global] 赋值**之前**创建并
/// 经 [install] 注入，否则会递归进入 overrides。
class DohDns {
  DohDns({
    required HttpClient bootstrapClient,
    List<DohEndpoint>? endpoints,
    this.minTtl = const Duration(seconds: 60),
    this.maxTtl = const Duration(seconds: 600),
  })  : _client = bootstrapClient,
        _endpoints = endpoints ?? DohEndpoint.defaults;

  static DohDns? _instance;

  /// 在设置 [HttpOverrides.global] 之前调用。
  static void install(DohDns dns) {
    _instance = dns;
  }

  static DohDns get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('DohDns.install() must run before HttpOverrides.global');
    }
    return i;
  }

  final HttpClient _client;
  final List<DohEndpoint> _endpoints;
  final Duration minTtl;
  final Duration maxTtl;

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<List<InternetAddress>>> _inflight = {};

  /// 解析主机名；已是 IP 则原样返回。
  Future<List<InternetAddress>> lookup(String host) {
    final key = host.trim().toLowerCase();
    if (key.isEmpty) {
      return Future.error(ArgumentError('empty host'));
    }

    final literal = InternetAddress.tryParse(key);
    if (literal != null) return Future.value([literal]);

    final cached = _cache[key];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return Future.value(List<InternetAddress>.from(cached.addrs));
    }

    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _lookupUncached(key);
    _inflight[key] = future;
    return future.whenComplete(() {
      if (identical(_inflight[key], future)) {
        _inflight.remove(key);
      }
    });
  }

  Future<List<InternetAddress>> _lookupUncached(String host) async {
    Object? lastError;
    for (final ep in _endpoints) {
      try {
        final result = await _queryEndpoint(ep, host);
        if (result.addrs.isEmpty) continue;
        final ttl = _clampTtl(result.ttl);
        _cache[host] = _CacheEntry(
          addrs: result.addrs,
          expires: DateTime.now().add(ttl),
        );
        jpLog(
          'DNS',
          'DoH hit $host → ${result.addrs} via ${ep.uri.host} ttl=${ttl.inSeconds}s',
        );
        return List<InternetAddress>.from(result.addrs);
      } catch (e) {
        lastError = e;
        jpLog('DNS', 'DoH miss ${ep.uri} for $host: $e');
      }
    }

    jpLog('DNS', 'DoH all failed for $host, fallback system lookup ($lastError)');
    final sys = await InternetAddress.lookup(host);
    if (sys.isEmpty) {
      throw SocketException('Failed host lookup: \'$host\'');
    }
    _cache[host] = _CacheEntry(
      addrs: sys,
      expires: DateTime.now().add(minTtl),
    );
    return sys;
  }

  Future<({List<InternetAddress> addrs, Duration ttl})> _queryEndpoint(
    DohEndpoint ep,
    String host,
  ) async {
    final uri = ep.uri.replace(queryParameters: {
      ...ep.uri.queryParameters,
      'name': host,
      'type': ep.typeParam,
    });
    final req = await _client.getUrl(uri);
    for (final h in ep.headers.entries) {
      req.headers.set(h.key, h.value);
    }
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw HttpException('DoH HTTP ${resp.statusCode}', uri: uri);
    }
    return parseDnsJson(body);
  }

  /// 解析 Cloudflare / Google / Aliyun 风格的 DNS JSON。
  static ({List<InternetAddress> addrs, Duration ttl}) parseDnsJson(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map) {
      throw const FormatException('DoH response not a JSON object');
    }
    final status = decoded['Status'];
    if (status != null && status != 0) {
      throw SocketException('DoH Status=$status');
    }
    final answer = decoded['Answer'];
    if (answer is! List || answer.isEmpty) {
      return (addrs: <InternetAddress>[], ttl: const Duration(seconds: 60));
    }

    final addrs = <InternetAddress>[];
    var minAnswerTtl = 600;
    for (final raw in answer) {
      if (raw is! Map) continue;
      final type = raw['type'];
      final data = raw['data']?.toString();
      if (data == null || data.isEmpty) continue;
      // 1=A, 28=AAAA；跳过 CNAME(5) 等
      if (type != 1 && type != 28) continue;
      final ip = InternetAddress.tryParse(data);
      if (ip == null) continue;
      addrs.add(ip);
      final ttl = raw['TTL'];
      if (ttl is int && ttl > 0 && ttl < minAnswerTtl) {
        minAnswerTtl = ttl;
      }
    }

    addrs.sort((a, b) {
      if (a.type == b.type) return 0;
      if (a.type == InternetAddressType.IPv4) return -1;
      return 1;
    });

    return (addrs: addrs, ttl: Duration(seconds: minAnswerTtl));
  }

  Duration _clampTtl(Duration ttl) {
    if (ttl < minTtl) return minTtl;
    if (ttl > maxTtl) return maxTtl;
    return ttl;
  }

  /// 公开 TTL 夹取，供单测。
  Duration clampTtlForTest(Duration ttl) => _clampTtl(ttl);

  /// 挂到业务 [HttpClient]：非 IP 主机经 DoH 得地址再连；URI 主机名不变。
  ///
  /// 注意：自定义 [HttpClient.connectionFactory] 时，Dart **不会**再自动
  /// `SecureSocket.secure`；HTTPS 必须在此返回已握手的安全套接字，否则会
  /// 出现 `400 The plain HTTP request was sent to HTTPS port`。
  void attachTo(HttpClient client) {
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      if (proxyHost != null && proxyPort != null) {
        return Socket.startConnect(proxyHost, proxyPort);
      }

      final host = uri.host;
      final port = uri.port == 0
          ? (uri.scheme == 'https' ? 443 : 80)
          : uri.port;
      final isHttps = uri.isScheme('https');

      InternetAddress addr;
      final literal = InternetAddress.tryParse(host);
      if (literal != null) {
        addr = literal;
      } else {
        try {
          final addrs = await lookup(host);
          if (addrs.isEmpty) {
            return isHttps
                ? SecureSocket.startConnect(host, port)
                : Socket.startConnect(host, port);
          }
          addr = addrs.first;
        } catch (e) {
          jpLog('DNS', 'connectionFactory fallback system for $host: $e');
          return isHttps
              ? SecureSocket.startConnect(host, port)
              : Socket.startConnect(host, port);
        }
      }

      if (!isHttps) {
        return Socket.startConnect(addr, port);
      }

      // TCP → IP，TLS SNI / 证书校验仍用原主机名
      Socket? pending;
      final future = () async {
        final task = await Socket.startConnect(addr, port);
        pending = await task.socket;
        return SecureSocket.secure(
          pending!,
          host: host,
          onBadCertificate: (_) => true,
        );
      }();
      return ConnectionTask.fromSocket(future, () {
        pending?.destroy();
      });
    };
  }
}

class DohEndpoint {
  const DohEndpoint({
    required this.uri,
    required this.typeParam,
    this.headers = const {},
  });

  final Uri uri;
  final String typeParam;
  final Map<String, String> headers;

  /// 国内阿里 / 腾讯 IP 字面量优先；Cloudflare 仅作末位兜底。
  static final List<DohEndpoint> defaults = [
    // 阿里云 AliDNS
    DohEndpoint(
      uri: Uri.parse('https://223.5.5.5/resolve'),
      typeParam: '1',
    ),
    DohEndpoint(
      uri: Uri.parse('https://223.6.6.6/resolve'),
      typeParam: '1',
    ),
    // 腾讯 DNSPod / doh.pub
    DohEndpoint(
      uri: Uri.parse('https://1.12.12.12/resolve'),
      typeParam: 'A',
    ),
    DohEndpoint(
      uri: Uri.parse('https://120.53.53.53/resolve'),
      typeParam: 'A',
    ),
    // 海外兜底（IP 字面量）
    DohEndpoint(
      uri: Uri.parse('https://1.1.1.1/dns-query'),
      typeParam: 'A',
      headers: const {'Accept': 'application/dns-json'},
    ),
  ];
}

class _CacheEntry {
  _CacheEntry({required this.addrs, required this.expires});
  final List<InternetAddress> addrs;
  final DateTime expires;
}
