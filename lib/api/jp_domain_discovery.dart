import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'jp_log.dart';

/// 荐片 API 根域发现（对齐桌面 5.0.4：OSS → DoH TXT → 日期盐）。
///
/// 缓存粒度为**根域**（如 `hzhnl.com` / `japi.zxfmj.com`）；
/// 非常规 japi 根域测活与建连时使用 `https://{rand6}.{root}`。
class JpDomainDiscovery {
  JpDomainDiscovery({http.Client? httpClient, Random? random})
      : _http = httpClient ?? http.Client(),
        _random = random ?? Random.secure();

  final http.Client _http;
  final Random _random;

  static const String fallbackRoot = 'japi.zxfmj.com';
  static const String dohName = 'pyvemnlu.cc';
  static const String lastApiRootKey = 'last_api_root';
  static const String apiDomainsKey = 'api_domains';
  /// 旧版缓存的完整 baseUrl（含 `/api`）。
  static const String legacyLastApiDomainKey = 'last_api_domain';

  static const Set<String> badRoots = {
    'api.ipixiv.com',
    'release.ipixiv.com',
  };

  static const List<String> _ossUrls = [
    'https://jdomain.oss-accelerate.aliyuncs.com/domain.txt',
  ];

  static const List<String> _dohEndpoints = [
    'https://dns.alidns.com/resolve',
    'https://doh.pub/dns-query',
    'https://1.1.1.1/dns-query',
  ];

  static const List<String> _dateSalts = [
    'JPQrpjbecpwX',
    'JP!o^rWD9eZQ',
    'JPjEx2EPKGoe',
    'JPUMqC2zwm7Q',
    'JPWmLQZndRhi',
  ];

  static final RegExp _ipv4Host = RegExp(
    r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d{1,5})?$',
  );

  static bool isBadRoot(String root) {
    final r = root.trim().toLowerCase();
    if (r.isEmpty) return true;
    if (badRoots.contains(r)) return true;
    // 旧全 URL 误当根域时
    for (final b in badRoots) {
      if (r.contains(b)) return true;
    }
    return false;
  }

  /// 从旧 `https://host/api` 抽出 host；失败返回 null。
  static String? rootFromLegacyBaseUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final u = Uri.parse(url.contains('://') ? url : 'https://$url');
      final host = u.host;
      if (host.isEmpty) return null;
      return host;
    } catch (_) {
      return null;
    }
  }

  /// 由根域生成本会话 API base（以 `/api` 结尾）。
  String buildApiBaseUrl(String root) {
    final origin = _originForRoot(root);
    return '$origin/api';
  }

  /// 发现结果：可用根域 + 本次从 OSS/DoH 拉到的列表（供缓存）。
  ///
  /// [excludeRoots] 中的根域跳过（例如刚发生 DNS 失败的节点）。
  Future<({String root, List<String>? fetchedList})?> resolve({
    String? seedRoot,
    List<String>? seedDomainList,
    Set<String> excludeRoots = const {},
  }) async {
    final exclude = {
      for (final e in excludeRoots) e.trim().toLowerCase(),
    };

    bool skipped(String root) {
      final r = root.trim();
      if (r.isEmpty || isBadRoot(r)) return true;
      if (exclude.contains(r.toLowerCase())) return true;
      return false;
    }

    final seeded = <String>[];
    void addAll(Iterable<String>? xs) {
      if (xs == null) return;
      for (final x in xs) {
        final r = x.trim();
        if (skipped(r)) continue;
        if (!seeded.contains(r)) seeded.add(r);
      }
    }

    addAll(seedRoot == null ? null : [seedRoot]);
    addAll(seedDomainList);
    if (!skipped(fallbackRoot) && !seeded.contains(fallbackRoot)) {
      seeded.add(fallbackRoot);
    }

    jpLog('API', 'Domain discover seed: $seeded exclude=$exclude');
    var hit = await _probeRoots(seeded, skipped);
    if (hit != null) return (root: hit, fetchedList: null);

    for (final oss in _ossUrls) {
      final list = await _fetchOssDomainList(oss);
      if (list == null || list.isEmpty) continue;
      final filtered = list.where((r) => !skipped(r)).toList();
      jpLog('API', 'Domain discover OSS list: $filtered');
      hit = await _probeRoots(filtered, skipped);
      if (hit != null) return (root: hit, fetchedList: list);
    }

    for (final doh in _dohEndpoints) {
      final list = await _fetchDohTxtList(doh);
      if (list == null || list.isEmpty) continue;
      final filtered = list.where((r) => !skipped(r)).toList();
      jpLog('API', 'Domain discover DoH list: $filtered');
      hit = await _probeRoots(filtered, skipped);
      if (hit != null) return (root: hit, fetchedList: list);
    }

    final generated = _dateSaltRoots().where((r) => !skipped(r)).toList();
    jpLog('API', 'Domain discover date-salt list: $generated');
    hit = await _probeRoots(generated, skipped);
    if (hit != null) return (root: hit, fetchedList: generated);
    return null;
  }

  Future<String?> _probeRoots(
    List<String> roots,
    bool Function(String root) skipped,
  ) async {
    for (final root in roots) {
      final r = root.trim();
      if (skipped(r)) continue;
      // 同根域最多试 3 次随机子域，降低偶发 DNS 失败
      final attempts = r == fallbackRoot ? 1 : 3;
      for (var i = 0; i < attempts; i++) {
        final origin = _originForRoot(r);
        final ok = await probeOrigin(origin);
        if (ok) {
          jpLog('API', 'Domain discover hit root=$r origin=$origin');
          return r;
        }
      }
    }
    return null;
  }

  String _originForRoot(String root) {
    final r = root.trim();
    if (_ipv4Host.hasMatch(r)) {
      return 'http://$r';
    }
    if (r == fallbackRoot) {
      return 'https://$r';
    }
    return 'https://${_rand6()}.$r';
  }

  String _rand6() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final sb = StringBuffer();
    for (var i = 0; i < 6; i++) {
      sb.write(chars[_random.nextInt(chars.length)]);
    }
    return sb.toString();
  }

  /// 测活：`{origin}/api/v2/settings/appAuthConfig`，code==1。
  Future<bool> probeOrigin(String origin) async {
    final url = '$origin/api/v2/settings/appAuthConfig';
    try {
      final resp = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        jpLog('API', 'Domain probe fail $url: HTTP ${resp.statusCode}');
        return false;
      }
      final body = json.decode(resp.body);
      final ok = body is Map && body['code'] == 1;
      if (!ok) {
        jpLog('API', 'Domain probe fail $url: unexpected body');
      }
      return ok;
    } catch (e) {
      jpLog('API', 'Domain probe fail $url: $e');
      return false;
    }
  }

  Future<bool> probeApiBase(String apiBase) async {
    final base = apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;
    return probeOrigin(base);
  }

  Future<List<String>?> _fetchOssDomainList(String url) async {
    try {
      final resp = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      return _splitDomainList(resp.body.trim());
    } catch (e) {
      jpLog('API', 'OSS domain list fail: $e');
      return null;
    }
  }

  Future<List<String>?> _fetchDohTxtList(String endpoint) async {
    try {
      final uri = Uri.parse(endpoint).replace(queryParameters: {
        'name': dohName,
        'type': '16',
      });
      final resp = await _http.get(
        uri,
        headers: {'accept': 'application/dns-json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = json.decode(resp.body);
      if (body is! Map) return null;
      final answer = body['Answer'];
      if (answer is! List || answer.isEmpty) return null;
      final raw = answer.first is Map ? answer.first['data'] : null;
      if (raw is! String || raw.isEmpty) return null;
      // TXT 常为带引号的 JSON 字符串
      String payload = raw.trim();
      try {
        final decoded = json.decode(payload);
        if (decoded is String) payload = decoded;
      } catch (_) {
        if (payload.length >= 2 &&
            payload.startsWith('"') &&
            payload.endsWith('"')) {
          payload = payload.substring(1, payload.length - 1);
        }
      }
      return _splitDomainList(payload);
    } catch (e) {
      jpLog('API', 'DoH TXT fail ($endpoint): $e');
      return null;
    }
  }

  List<String> _splitDomainList(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !isBadRoot(s))
        .toList();
  }

  List<String> _dateSaltRoots() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final date = '$y-$m-$d';
    return _dateSalts.map((salt) {
      final hex = md5.convert(utf8.encode('$date$salt')).toString();
      return '${hex.substring(9, 19)}.com';
    }).toList();
  }
}
