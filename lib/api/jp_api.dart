import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import '../models/jp_models.dart';
import '../models/mubu_hive.dart';
import '../utils/detail_source_parse.dart';
import '../utils/cover_cdn.dart';
import '../utils/img_domain_probe.dart';
import 'jp_domain_discovery.dart';
import 'jp_log.dart';

/// 荐片 API 服务核心类 (单例)
///
/// 负责 API 根域发现、动态 CDN 图片域名、签名计算以及业务接口调用。
class JpApi {
  static const String _apiVersion = '504';

  String _apiRoot = JpDomainDiscovery.fallbackRoot;
  String _baseUrl = 'https://${JpDomainDiscovery.fallbackRoot}/api';
  String _imgDomain = '';
  List<String> _imgDomainCandidates = List<String>.from(kHardcodedImgDomainBackups);
  String _secret = '';
  bool _initialized = false;
  Future<void>? _initFuture;

  final JpDomainDiscovery _domainDiscovery = JpDomainDiscovery();

  /// 本会话内 DNS/解析失败过的根域，发现时跳过。
  final Set<String> _dnsFailedRoots = {};

  /// 防止并发请求同时触发多次换域。
  Future<bool>? _failoverInFlight;

  /// 必须 lazy：若 static 字段在 main 设 HttpOverrides 之前初始化，会漏掉 DoH factory。
  static HttpClient? _sharedHttpClient;
  static HttpClient get _cdnHttpClient =>
      _sharedHttpClient ??= HttpClient()..connectionTimeout = const Duration(seconds: 2);

  static final JpApi _instance = JpApi._();
  factory JpApi() => _instance;
  JpApi._();

  /// 获取当前活跃的 API 基础 URL
  String get baseUrl => _baseUrl;

  /// 当前 API 根域（不含随机子域前缀时的逻辑根）
  String get apiRoot => _apiRoot;

  /// 获取当前解析成功、可用的活跃图片/封面 CDN 域名
  String get imgDomain => _imgDomain;

  /// 封面失败换域候选（主域置首）
  List<String> get imgDomainCandidates =>
      List<String>.unmodifiable(_imgDomainCandidates);

  /// 客户端 API 初始化入口
  ///
  /// 优先加载合法根域缓存。若存在则立即可用，并在后台静默刷新。
  /// 若无缓存，则阻塞跑完整域名发现。
  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _doInit();
    return _initFuture;
  }

  Future<void> _doInit() async {
    try {
      final configBox = Hive.box<String>('config');
      await _migrateAndSanitizeApiRootCache(configBox);

      final cachedRoot = configBox.get(JpDomainDiscovery.lastApiRootKey);
      final cachedSecret = configBox.get('secret');
      final cachedImgDomain = configBox.get('last_img_domain');

      final hasValidCache = cachedRoot != null &&
          cachedRoot.isNotEmpty &&
          !JpDomainDiscovery.isBadRoot(cachedRoot) &&
          cachedSecret != null &&
          cachedSecret.isNotEmpty;

      if (hasValidCache) {
        _apiRoot = cachedRoot;
        _baseUrl = _domainDiscovery.buildApiBaseUrl(_apiRoot);
        _secret = cachedSecret;
        if (cachedImgDomain != null && cachedImgDomain.isNotEmpty) {
          _imgDomain = cachedImgDomain;
        } else {
          _imgDomain = 'static2.gutaike.com';
        }
        _imgDomainCandidates = mergeImgDomainCandidates(primary: _imgDomain);
        _initialized = true;
        unawaited(_backgroundRefresh(isFirstInit: false));
        return;
      }

      await _backgroundRefresh(isFirstInit: true);
      _initialized = true;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  /// 迁移旧 `last_api_domain` 全 URL → `last_api_root`，并清除劣质域。
  Future<void> _migrateAndSanitizeApiRootCache(Box<String> configBox) async {
    var root = configBox.get(JpDomainDiscovery.lastApiRootKey);
    final legacy = configBox.get(JpDomainDiscovery.legacyLastApiDomainKey);

    if ((root == null || root.isEmpty) && legacy != null && legacy.isNotEmpty) {
      root = JpDomainDiscovery.rootFromLegacyBaseUrl(legacy);
      if (root != null && root.isNotEmpty) {
        await configBox.put(JpDomainDiscovery.lastApiRootKey, root);
        jpLog('API', 'Migrated legacy last_api_domain → root=$root');
      }
    }

    if (root != null && JpDomainDiscovery.isBadRoot(root)) {
      jpLog('API', 'Purging bad API root cache: $root');
      await configBox.delete(JpDomainDiscovery.lastApiRootKey);
      root = null;
    }

    if (legacy != null) {
      final legacyRoot = JpDomainDiscovery.rootFromLegacyBaseUrl(legacy);
      if (legacyRoot != null && JpDomainDiscovery.isBadRoot(legacyRoot)) {
        await configBox.delete(JpDomainDiscovery.legacyLastApiDomainKey);
      }
    }

    // 清理缓存的域名列表中的劣质项
    final rawList = configBox.get(JpDomainDiscovery.apiDomainsKey);
    if (rawList != null && rawList.isNotEmpty) {
      try {
        final decoded = json.decode(rawList);
        if (decoded is List) {
          final cleaned = decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty && !JpDomainDiscovery.isBadRoot(e))
              .toList();
          await configBox.put(JpDomainDiscovery.apiDomainsKey, json.encode(cleaned));
        }
      } catch (_) {
        await configBox.delete(JpDomainDiscovery.apiDomainsKey);
      }
    }
  }

  Future<void> _backgroundRefresh({required bool isFirstInit}) async {
    try {
      final configBox = Hive.box<String>('config');

      if (isFirstInit) {
        final root = await _discoverRoot(configBox);
        if (root == null) throw Exception('无法连接到荐片服务器');
        _applyApiRoot(root);
        await configBox.put(JpDomainDiscovery.lastApiRootKey, root);
        await configBox.put(JpDomainDiscovery.legacyLastApiDomainKey, _baseUrl);
      } else {
        // 静默全量发现（p7）；成功则切换根域并换新随机会话 URL
        final root = await _discoverRoot(configBox);
        if (root != null) {
          _applyApiRoot(root);
          await configBox.put(JpDomainDiscovery.lastApiRootKey, root);
          await configBox.put(JpDomainDiscovery.legacyLastApiDomainKey, _baseUrl);
        } else {
          // 发现失败则尝试当前根域换新随机子域
          final sessionBase = _domainDiscovery.buildApiBaseUrl(_apiRoot);
          if (await _domainDiscovery.probeApiBase(sessionBase)) {
            _baseUrl = sessionBase;
            await configBox.put(JpDomainDiscovery.legacyLastApiDomainKey, _baseUrl);
          } else {
            jpLog('API', 'Background rediscover failed; keeping $_baseUrl');
          }
        }
      }

      await _loadConfig();
    } catch (e, s) {
      jpLog('API', 'Background refresh failed: $e\n$s');
      if (isFirstInit) rethrow;
    }
  }

  Future<String?> _discoverRoot(
    Box<String> configBox, {
    Set<String> excludeRoots = const {},
  }) async {
    final seedRoot = configBox.get(JpDomainDiscovery.lastApiRootKey);
    List<String>? seedList;
    final raw = configBox.get(JpDomainDiscovery.apiDomainsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          seedList = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    final exclude = {...excludeRoots, ..._dnsFailedRoots};
    final result = await _domainDiscovery.resolve(
      seedRoot: seedRoot,
      seedDomainList: seedList,
      excludeRoots: exclude,
    );
    if (result == null) return null;
    if (result.fetchedList != null && result.fetchedList!.isNotEmpty) {
      await configBox.put(
        JpDomainDiscovery.apiDomainsKey,
        json.encode(result.fetchedList),
      );
    }
    return result.root;
  }

  void _applyApiRoot(String root) {
    _apiRoot = root;
    _baseUrl = _domainDiscovery.buildApiBaseUrl(root);
    jpLog('API', 'Active API root=$_apiRoot baseUrl=$_baseUrl');
  }

  bool _isHostLookupFailure(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup')) return true;
    if (s.contains('nodename nor servname')) return true;
    if (e is SocketException) {
      if (e.osError?.errorCode == 8) return true;
      final msg = (e.message).toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('nodename nor servname')) {
        return true;
      }
    }
    return false;
  }

  /// DNS/主机解析失败后换根域；成功返回 true。
  Future<bool> _failoverAfterDnsFailure() {
    final existing = _failoverInFlight;
    if (existing != null) return existing;
    final future = _doFailoverAfterDnsFailure();
    _failoverInFlight = future;
    return future.whenComplete(() {
      if (identical(_failoverInFlight, future)) {
        _failoverInFlight = null;
      }
    });
  }

  Future<bool> _doFailoverAfterDnsFailure() async {
    final failed = _apiRoot;
    _dnsFailedRoots.add(failed);
    jpLog('API', 'DNS/host lookup failed for root=$failed; failing over...');

    try {
      final configBox = Hive.box<String>('config');
      final cached = configBox.get(JpDomainDiscovery.lastApiRootKey);
      if (cached != null && cached == failed) {
        await configBox.delete(JpDomainDiscovery.lastApiRootKey);
      }

      final root = await _discoverRoot(
        configBox,
        excludeRoots: {failed},
      );
      if (root == null) {
        jpLog('API', 'Failover discover returned no root');
        return false;
      }
      _applyApiRoot(root);
      await configBox.put(JpDomainDiscovery.lastApiRootKey, root);
      await configBox.put(JpDomainDiscovery.legacyLastApiDomainKey, _baseUrl);
      // 换域后尽量刷新 secret（无签名接口也可能仍可用）
      try {
        final initResp = await http
            .get(
              Uri.parse('$_baseUrl/v2/sys/init'),
              headers: const {
                'Content-Type': 'application/json',
                'User-Agent': 'jianpian-linux/1.0',
              },
            )
            .timeout(const Duration(seconds: 10));
        if (initResp.statusCode == 200) {
          final body = json.decode(initResp.body);
          final data = body is Map ? body['data'] : null;
          final secret = data is Map ? data['secret'] : null;
          if (secret is String && secret.isNotEmpty) {
            _secret = secret;
            await configBox.put('secret', _secret);
          }
        }
      } catch (e) {
        jpLog('API', 'Failover sys/init soft-fail: $e');
      }
      jpLog('API', 'Failover success → $_apiRoot');
      return true;
    } catch (e, s) {
      jpLog('API', 'Failover error: $e\n$s');
      return false;
    }
  }

  /// 测试指定图片/封面 CDN 域名的连通性。
  ///
  /// 只看状态码和 Content-Type，拿到响应头后关掉连接，不把测速图正文下完。
  Future<bool> _testImgDomain(String domain, String path) async {
    if (domain.isEmpty) return false;
    try {
      final request = await _cdnHttpClient
          .getUrl(Uri.parse('https://$domain$path'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      final success = imageProbeAccepts(
        statusCode: response.statusCode,
        mimeType: response.headers.contentType?.mimeType,
      );
      try {
        final socket = await response.detachSocket();
        socket.destroy();
      } catch (_) {}

      jpLog(
        'CDN',
        'Tested domain: $domain | success: $success | statusCode: ${response.statusCode}',
      );
      return success;
    } catch (e) {
      jpLog('CDN', 'Tested domain: $domain | failed with exception: $e');
      return false;
    }
  }

  Future<String?> _raceImgDomains(
    List<String> domains,
    String path, {
    String prefer = '',
  }) async {
    if (domains.isEmpty) return null;
    final nodeBox = Hive.box<NodeSpeedRecord>('node_speeds');
    final now = DateTime.now().millisecondsSinceEpoch;
    final ttlMs = 24 * 60 * 60 * 1000; // 24 hours

    String? bestCachedDomain;
    int bestCachedLatency = 999999;
    for (final domain in domains) {
      final record = nodeBox.get(domain);
      if (record != null && (now - record.testedAtEpoch) < ttlMs) {
        if (record.latencyMs < 500 && record.latencyMs < bestCachedLatency) {
          bestCachedLatency = record.latencyMs;
          bestCachedDomain = domain;
        }
      }
    }
    if (bestCachedDomain != null) {
      jpLog('CDN', 'Using cached fast Img domain: $bestCachedDomain (${bestCachedLatency}ms)');
      return bestCachedDomain;
    }

    return pickImgDomain(
      prefer: prefer,
      domains: domains,
      probe: (domain) async {
        final start = DateTime.now().millisecondsSinceEpoch;
        final success = await _testImgDomain(domain, path);
        final latency = DateTime.now().millisecondsSinceEpoch - start;
        await nodeBox.put(
          domain,
          NodeSpeedRecord(
            domainOrUrl: domain,
            latencyMs: success ? latency : 99999,
            testedAtEpoch: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        return success;
      },
    );
  }

  /// 加载系统配置（重点获取图片 CDN 域名与解密/防爬 Secret）
  /// 
  /// 若默认图片域名无法连通，将从服务器拉取备用域名列表并进行并发测速，
  /// 若均不可用，会自动降级使用内置硬编码的 CDN 域名（如 static2.gutaike.com）。
  /// 无论默认域是否可用，都会合并 package + 硬编码为 [_imgDomainCandidates]（主域置首）。
  Future<void> _loadConfig() async {
    try {
      final authResp = await _get('/v2/settings/appAuthConfig');
      String testPath = '';
      if (authResp != null && authResp['data'] != null) {
        _imgDomain = authResp['data']['imgDomain'] ?? '';
        testPath = authResp['data']['image'] ?? '';
      }
      jpLog('CDN', 'Loaded appAuthConfig. Default imgDomain: $_imgDomain, testPath: $testPath');

      if (testPath.isEmpty) {
        testPath = '/upload/video/2023/12/09/0cff0e65030b486db58408abeeefd85b.jpg';
      }

      // 始终拉取备用域列表，供封面失败换域（不改变单测速图选主逻辑）
      final fallbackResp = await _get('/v2/settings/packageDomainConfig');
      List<String> packageDomains = [];
      if (fallbackResp != null && fallbackResp['data'] != null) {
        final domainsStr = fallbackResp['data']['imgDomain'] as String? ?? '';
        packageDomains = domainsStr
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      jpLog('CDN', 'Package img domains: $packageDomains');

      // 主域和备用域一起探。主域已死时不必等满它自己的超时。
      final probeDomains = mergeImgDomainCandidates(
        primary: _imgDomain,
        fromPackage: packageDomains,
      );
      jpLog('CDN', 'Racing img domains: $probeDomains prefer=$_imgDomain');
      final bestDomain = await _raceImgDomains(
        probeDomains,
        testPath,
        prefer: _imgDomain,
      );
      if (bestDomain != null) {
        _imgDomain = bestDomain;
        jpLog('CDN', 'Selected img domain: $_imgDomain');
      } else if (probeDomains.isNotEmpty) {
        _imgDomain = probeDomains.first;
        jpLog(
          'CDN',
          'No img domain probe succeeded. Using first candidate: $_imgDomain',
        );
      }

      _imgDomainCandidates = mergeImgDomainCandidates(
        primary: _imgDomain,
        fromPackage: packageDomains,
      );

      jpLog('CDN', 'Final active imgDomain resolved to: $_imgDomain');
      jpLog('CDN', 'imgDomainCandidates: $_imgDomainCandidates');
      
      final configBox = Hive.box<String>('config');
      await configBox.put('last_img_domain', _imgDomain);

      // 初始化系统参数，拉取接口签名所需的安全 Secret 并本地缓存
      final initResp = await _get('/v2/sys/init');
      if (initResp != null && initResp['data'] != null && initResp['data']['secret'] != null) {
        _secret = initResp['data']['secret'];
        await configBox.put('secret', _secret);
      }
    } catch (e, s) {
      jpLog('CDN', 'Error in _loadConfig: $e\n$s');
      _imgDomainCandidates = mergeImgDomainCandidates(primary: _imgDomain);
    }
  }

  /// 计算并填充 API 安全校验签名 Header
  ///
  /// 签名规则：MD5(version + timestamp + secret)，version 对齐桌面 5.0.4 为 504。
  Map<String, String> _signedHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'jianpian-linux/1.0',
    };
    if (_secret.isNotEmpty) {
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final sig = md5.convert(utf8.encode('$_apiVersion$ts$_secret')).toString();
      headers['version'] = _apiVersion;
      headers['timestamp'] = ts;
      headers['signature'] = sig;
    }
    return headers;
  }

  /// 底层通用的 HTTP GET 请求方法
  ///
  /// 超时/网络异常默认重试；若判定为 DNS/主机解析失败，则换根域后再试一次。
  Future<dynamic> _get(String path, {int retries = 2}) async {
    int attempt = 0;
    var didDnsFailover = false;
    while (true) {
      try {
        final resp = await http
            .get(Uri.parse('$_baseUrl$path'), headers: _signedHeaders())
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final b = json.decode(resp.body);
          if (b['code'] == 1 || b['code'] == 0) return b;
        }
        return null;
      } catch (e) {
        if (!didDnsFailover && _isHostLookupFailure(e)) {
          didDnsFailover = true;
          final ok = await _failoverAfterDnsFailure();
          if (ok) {
            jpLog('API', 'Retrying $path after DNS failover → $_baseUrl');
            continue;
          }
        }
        attempt++;
        if (attempt > retries) {
          jpLog('API', 'Request to $path failed after $retries retries: $e');
          rethrow;
        }
        jpLog('API', 'Request to $path failed (attempt $attempt/$retries) with error: $e. Retrying in 1s...');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  // --- 业务接口 (Content APIs) ---

  /// 拉取大类分类目录（如：电影、电视剧、短剧、动漫、综艺等）
  Future<List<CategoryItem>> getHomeCategorys() async {
    final resp = await _get('/v2/settings/homeCategory');
    if (resp != null && resp['data'] != null) {
      return (resp['data'] as List).map((j) => CategoryItem.fromJson(j)).toList();
    }
    return [];
  }

  /// 根据大类 ID 获取其下方推荐板块的 Tags 标签列表
  Future<List<TagItem>> getHomeTags(int categoryId) async {
    final resp = await _get('/pc_dyTag/list?category_id=$categoryId');
    if (resp != null && resp['data'] != null) {
      return (resp['data'] as List).map((j) => TagItem.fromJson(j)).toList();
    }
    return [];
  }

  /// 根据标签 ID 及模板类型分页拉取视频卡片集合
  Future<List<VideoItem>> getTagVideos(int tagId, {int tpl = 1, int page = 1, int count = 30}) async {
    final resp = await _get('/pc_dyTag/tpl${tpl}_list?id=$tagId&page=$page&count=$count');
    if (resp != null && resp['data'] != null) {
      return (resp['data'] as List).map((j) => VideoItem.fromTagJson(j)).toList();
    }
    return [];
  }

  /// 运营手推片：`data` 为 tagId → 视频列表。失败返回空 map。
  Future<Map<int, List<VideoItem>>> getHomeHandData(int categoryId) async {
    try {
      final resp = await _get('/dyTag/hand_data?category_id=$categoryId');
      final raw = resp?['data'];
      if (raw is! Map) return {};
      final out = <int, List<VideoItem>>{};
      for (final entry in raw.entries) {
        final tagId = int.tryParse(entry.key.toString());
        final list = entry.value;
        if (tagId == null || list is! List) continue;
        out[tagId] = list
            .whereType<Map>()
            .map((j) => VideoItem.fromTagJson(Map<String, dynamic>.from(j)))
            .toList();
      }
      return out;
    } catch (e) {
      jpLog('API', 'getHomeHandData($categoryId) failed: $e');
      return {};
    }
  }

  /// 全局视频搜索接口
  ///
  /// 关键词已进行 URL 安全编码。返回列表按：精确 title → title/original_name 包含 → 其余（稳定排序）。
  Future<({List<VideoItem> videos, int total})> search(String keyword, {int page = 1}) async {
    final encodedKey = Uri.encodeComponent(keyword);
    final resp = await _get('/v2/search/videoV2?key=$encodedKey&page=$page');
    if (resp != null && resp['data'] != null && resp['data'] is List) {
      final raw = (resp['data'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final sorted = _sortSearchResults(raw, keyword);
      final videos = sorted.map(VideoItem.fromSearchJson).toList();
      final total = (resp['total'] as num?)?.toInt() ?? videos.length;
      return (videos: videos, total: total);
    }
    return (videos: <VideoItem>[], total: 0);
  }

  /// 精确匹配优先，其次标题/原名包含关键词；同档保持相对顺序。
  List<Map<String, dynamic>> _sortSearchResults(
    List<Map<String, dynamic>> items,
    String keyword,
  ) {
    final kw = keyword.trim();
    if (kw.isEmpty || items.length <= 1) return items;

    int rank(Map<String, dynamic> j) {
      final title = (j['title'] ?? '').toString();
      final original = (j['original_name'] ?? '').toString();
      if (title == kw) return 0;
      if (title.contains(kw) || original.contains(kw)) return 1;
      return 2;
    }

    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final c = rank(a.$2).compareTo(rank(b.$2));
      if (c != 0) return c;
      return a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// 获取影片详情数据（包含全部待测速的播放线路列表）
  /// 
  /// 特殊逻辑：如果是短剧（[isShort] 为 true），将分流请求短剧专属路由 `/detail?vid=$id`，
  /// 否则请求常规视频路由 `/video/detailv2?id=$id`。避开两者 ID 空间冲突。
  Future<VideoDetail?> getVideoDetail(int id, {bool isShort = false}) async {
    final resp = isShort
        ? await _get('/detail?vid=$id')
        : await _get('/video/detailv2?id=$id');
    if (resp != null && resp['data'] != null) {
      return VideoDetail.fromJson(resp['data']);
    }
    return null;
  }

  /// Full signed GET response (for tooling / fixture generation).
  Future<Map<String, dynamic>?> getRawResponse(String path) async {
    final resp = await _get(path);
    if (resp is Map<String, dynamic>) return resp;
    return null;
  }


  /// 拉取高级分类筛选的可选项列表
  Future<List<FilterGroup>> getFilterOptions(int fcatePid) async {
    final resp = await _get('/crumb/filterOptions?fcate_pid=$fcatePid');
    if (resp != null && resp['data'] != null && resp['data'] is List) {
      return (resp['data'] as List).map((j) => FilterGroup.fromJson(j)).toList();
    }
    return [];
  }

  /// 多维条件筛选列表获取（带分页）
  /// 
  /// 针对短剧（PID 67，走 crumb/shortList，用 category_id 替代 type，免传地区和年份）、
  /// 纪录片（PID 50，固定主类型 type=28，子类代入 category_id）
  /// 以及普通大类进行了严格的服务端传参兼容适配。
  Future<List<VideoItem>> getFilteredVideos({
    required int fcatePid,
    String type = '',
    String area = '',
    String year = '',
    String sort = '',
    int page = 1,
  }) async {
    final String path;
    final String queryParams;

    if (fcatePid == 67) {
      path = '/crumb/shortList';
      queryParams = 'fcate_pid=$fcatePid&category_id=$type&sort=$sort&page=$page';
    } else if (fcatePid == 50) {
      path = '/crumb/list';
      queryParams = 'fcate_pid=$fcatePid&type=28&category_id=$type&area=$area&year=$year&sort=$sort&page=$page';
    } else {
      path = '/crumb/list';
      queryParams = 'fcate_pid=$fcatePid&type=$type&area=$area&year=$year&sort=$sort&page=$page';
    }

    final resp = await _get('$path?$queryParams');
    if (resp != null && resp['data'] != null && resp['data'] is List) {
      return (resp['data'] as List).map((j) => VideoItem.fromTagJson(j)).toList();
    }
    return [];
  }
}

/// 业务分类实体模型
class CategoryItem {
  final int id;
  final String name;
  CategoryItem({required this.id, required this.name});
  factory CategoryItem.fromJson(Map<String, dynamic> json) =>
      CategoryItem(id: json['id'] ?? 0, name: json['name'] ?? '');
}

/// 标签分类板块模型
class TagItem {
  final int id;
  final String name;
  final int template;
  TagItem({required this.id, required this.name, this.template = 1});
  factory TagItem.fromJson(Map<String, dynamic> json) =>
      TagItem(id: json['id'] ?? 0, name: json['name'] ?? '', template: json['template'] ?? 1);
}

/// 视频播放源信息模型
class VideoSource {
  /// 线路/清晰度组名（例如：极速蓝光、高清线路1、LZ线路）
  final String name;
  /// 本集名称或子集说明（例如：第01集、20220913）
  final String sourceName;
  /// 实际的 M3U8/HLS 播放地址
  final String url;
  /// 项级配置名（source_config_name），与 name 不一致时更准确
  final String sourceConfigName;
  /// API `weight`，集数主键（优先于 source_name 匹配）
  final String weight;
  /// 片头时长（秒），来自 time_data.titles_duration
  final int titlesDurationSec;
  /// 片尾时长（秒），来自 time_data.trailer_duration
  final int trailerDurationSec;
  /// 在 source_list_source 中的出现顺序，用于同分打破平局
  final int listOrder;
  /// 并发测试得出的延迟网速（毫秒），若超时通常置为 999999
  int? speedMs;
  /// 线路可用状态标志。若握手或视频流校验失败会置为 false
  bool usable = true;
  /// Duration in seconds from API time_data.total_duration (fallback).
  int? apiDurationSec;

  VideoSource({
    required this.name,
    required this.sourceName,
    required this.url,
    this.sourceConfigName = '',
    this.weight = '',
    this.titlesDurationSec = 0,
    this.trailerDurationSec = 0,
    this.listOrder = 0,
    this.speedMs,
    this.apiDurationSec,
    bool usable = true,
  }) : usable = usable;
}

/// 视频详情（含剧集与线路）数据模型
class VideoDetail {
  final int id;
  final String title;
  final String description;
  final String score;
  final String year;
  final List<VideoSource> sources;

  VideoDetail({
    required this.id,
    required this.title,
    this.description = '',
    this.score = '',
    this.year = '',
    this.sources = const [],
  });

  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    final sources = parseDetailSources(json)
        .map(
          (f) => VideoSource(
            name: f.name,
            sourceName: f.sourceName,
            url: f.url,
            sourceConfigName: f.sourceConfigName,
            weight: f.weight,
            titlesDurationSec: f.titlesDurationSec,
            trailerDurationSec: f.trailerDurationSec,
            listOrder: f.listOrder,
            usable: f.usable,
            apiDurationSec: f.apiDurationSec,
          ),
        )
        .toList();

    return VideoDetail(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      score: json['score']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      sources: sources,
    );
  }

  /// 获取当前线路集合中的首选/默认播放 URL（首集 + 质量/延迟策略需由 SourcePicker 在 UI 层应用）
  String? get bestUrl {
    if (sources.isEmpty) return null;
    final first = sources.first;
    final ref = first.weight.isNotEmpty ? first.weight : first.sourceName;
    final sameEp = sources.where(
      (s) =>
          (s.weight.isNotEmpty ? s.weight == ref : s.sourceName == ref) &&
          s.usable,
    );
    if (sameEp.isEmpty) return first.url;
    return sameEp.first.url;
  }
}
