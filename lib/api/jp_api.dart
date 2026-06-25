import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import '../models/jp_models.dart';
import '../models/mubu_hive.dart';
import 'jp_log.dart';

/// 荐片 API 服务核心类 (单例)
/// 
/// 负责 API 域名的连通性测试、动态 CDN 图片域名的选择、动态安全签名计算以及业务接口调用。
class JpApi {
  // 固定备选 API 域名列表，在启动时进行动态测速，选择首个可连通的域名
  static const List<String> _fixedDomains = [
    'japi.zxfmj.com',
    'api.ipixiv.com',
    'release.ipixiv.com',
  ];

  String _baseUrl = 'https://japi.zxfmj.com/api';
  String _imgDomain = '';
  String _secret = '';
  bool _initialized = false;
  Future<void>? _initFuture;

  static final HttpClient _sharedHttpClient = HttpClient()..connectionTimeout = const Duration(seconds: 2);

  static final JpApi _instance = JpApi._();
  factory JpApi() => _instance;
  JpApi._();

  /// 获取当前活跃的 API 基础 URL
  String get baseUrl => _baseUrl;

  /// 获取当前解析成功、可用的活跃图片/封面 CDN 域名
  String get imgDomain => _imgDomain;

  /// 客户端 API 初始化入口
  /// 
  /// 优先加载本地持久化缓存。若存在缓存立即返回成功，并在后台静默刷新验证。
  /// 若无缓存，则并发测试可用域名并初始化配置。
  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _doInit();
    return _initFuture;
  }

  Future<void> _doInit() async {
    try {
      final configBox = Hive.box<String>('config');
      final cached = configBox.get('last_api_domain');
      final cachedSecret = configBox.get('secret');
      final cachedImgDomain = configBox.get('last_img_domain');

      final hasValidCache = cached != null && cachedSecret != null && cachedSecret.isNotEmpty;

      if (hasValidCache) {
        _baseUrl = cached;
        _secret = cachedSecret;
        if (cachedImgDomain != null && cachedImgDomain.isNotEmpty) {
          _imgDomain = cachedImgDomain;
        } else {
          _imgDomain = 'static2.gutaike.com';
        }
        _initialized = true;
        // 懒加载：立即返回成功并让 UI 渲染，同时在后台静默测速刷新
        unawaited(_backgroundRefresh(isFirstInit: false));
        return;
      }

      // 无缓存，必须全量阻塞测速
      await _backgroundRefresh(isFirstInit: true);
      _initialized = true;
    } catch (e) {
      _initFuture = null; // 允许失败重试
      rethrow;
    }
  }

  Future<void> _backgroundRefresh({required bool isFirstInit}) async {
    try {
      final configBox = Hive.box<String>('config');
      String? bestApiUrl;

      if (isFirstInit) {
        bestApiUrl = await _raceApiDomains(_fixedDomains);
        if (bestApiUrl == null) throw Exception('无法连接到荐片服务器');
        _baseUrl = bestApiUrl;
        await configBox.put('last_api_domain', _baseUrl);
      } else {
        bool currentOk = await _testDomain(_baseUrl);
        if (!currentOk) {
          bestApiUrl = await _raceApiDomains(_fixedDomains);
          if (bestApiUrl != null) {
            _baseUrl = bestApiUrl;
            await configBox.put('last_api_domain', _baseUrl);
          }
        }
      }

      await _loadConfig();
    } catch (e, s) {
      jpLog('API', 'Background refresh failed: $e\n$s');
    }
  }

  Future<String?> _raceApiDomains(List<String> domains) async {
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
      jpLog('API', 'Using cached fast API domain: $bestCachedDomain (${bestCachedLatency}ms)');
      return 'https://$bestCachedDomain/api';
    }

    final completer = Completer<String?>();
    int failedCount = 0;

    for (final domain in domains) {
      final url = 'https://$domain/api';
      final start = DateTime.now().millisecondsSinceEpoch;
      _testDomain(url).then((success) {
        final latency = DateTime.now().millisecondsSinceEpoch - start;
        if (success) {
          nodeBox.put(domain, NodeSpeedRecord(domainOrUrl: domain, latencyMs: latency, testedAtEpoch: DateTime.now().millisecondsSinceEpoch));
          if (!completer.isCompleted) completer.complete(url);
        } else {
          nodeBox.put(domain, NodeSpeedRecord(domainOrUrl: domain, latencyMs: 99999, testedAtEpoch: DateTime.now().millisecondsSinceEpoch));
          failedCount++;
          if (failedCount == domains.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      });
    }
    return completer.future;
  }

  /// 测试指定 API 域名的连通性
  /// 
  /// 发送基础 Auth 配置请求，要求 HTTP 返回 200 且业务 code == 1 视为连通
  Future<bool> _testDomain(String url) async {
    try {
      final resp = await http
          .get(Uri.parse('$url/v2/settings/appAuthConfig'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body['code'] == 1) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 测试指定图片/封面 CDN 域名的连通性
  /// 
  /// 使用共享的 HttpClient (Keep-Alive) 进行测速，提升后续请求的连接复用率
  Future<bool> _testImgDomain(String domain, String path) async {
    if (domain.isEmpty) return false;
    try {
      final request = await _sharedHttpClient.getUrl(Uri.parse('https://$domain$path'))
          .timeout(const Duration(seconds: 2));
      // 移除 'Connection: close'，允许复用
      final response = await request.close().timeout(const Duration(seconds: 2));
      final success = response.statusCode == HttpStatus.ok;
      
      // 读空响应体让连接能够放回池中复用
      await response.drain().timeout(const Duration(seconds: 1));
      
      jpLog('CDN', 'Tested domain: $domain | success: $success | statusCode: ${response.statusCode}');
      return success;
    } catch (e) {
      jpLog('CDN', 'Tested domain: $domain | failed with exception: $e');
      return false;
    }
  }

  Future<String?> _raceImgDomains(List<String> domains, String path) async {
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

    final completer = Completer<String?>();
    int failedCount = 0;

    for (final domain in domains) {
      final start = DateTime.now().millisecondsSinceEpoch;
      _testImgDomain(domain, path).then((success) {
        final latency = DateTime.now().millisecondsSinceEpoch - start;
        if (success) {
          nodeBox.put(domain, NodeSpeedRecord(domainOrUrl: domain, latencyMs: latency, testedAtEpoch: DateTime.now().millisecondsSinceEpoch));
          if (!completer.isCompleted) completer.complete(domain);
        } else {
          nodeBox.put(domain, NodeSpeedRecord(domainOrUrl: domain, latencyMs: 99999, testedAtEpoch: DateTime.now().millisecondsSinceEpoch));
          failedCount++;
          if (failedCount == domains.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      });
    }
    return completer.future;
  }

  /// 加载系统配置（重点获取图片 CDN 域名与解密/防爬 Secret）
  /// 
  /// 若默认图片域名无法连通，将从服务器拉取备用域名列表并进行并发测速，
  /// 若均不可用，会自动降级使用内置硬编码的 CDN 域名（如 static2.gutaike.com）。
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

      // 验证默认图片域名是否可以连通
      final defaultOk = await _testImgDomain(_imgDomain, testPath);
      jpLog('CDN', 'Default domain check: $_imgDomain is working: $defaultOk');

      if (!defaultOk) {
        jpLog('CDN', 'Default domain failed. Fetching backup domains...');
        // 从云端拉取多组备选图片域名
        final fallbackResp = await _get('/v2/settings/packageDomainConfig');
        List<String> backupDomains = [];
        if (fallbackResp != null && fallbackResp['data'] != null) {
          final domainsStr = fallbackResp['data']['imgDomain'] as String? ?? '';
          backupDomains = domainsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
        jpLog('CDN', 'Backup domains list: $backupDomains');
        
        // 压入硬编码的安全备用图片域名
        const hardcodedBackups = ['static2.gutaike.com', 'static.shaxyt.com'];
        for (final fallback in hardcodedBackups) {
          if (!backupDomains.contains(fallback)) {
            backupDomains.add(fallback);
          }
        }
        jpLog('CDN', 'Final testing list (including hardcoded fallback): $backupDomains');

        // 并发进行备选域名测速 (竞速模式)
        final bestDomain = await _raceImgDomains(backupDomains, testPath);
        
        if (bestDomain != null) {
          _imgDomain = bestDomain;
          jpLog('CDN', 'Selected backup domain: $_imgDomain');
        } else if (backupDomains.isNotEmpty) {
          _imgDomain = backupDomains.first;
          jpLog('CDN', 'None of the tested backup domains succeeded. Using first backup domain: $_imgDomain');
        }
      }

      jpLog('CDN', 'Final active imgDomain resolved to: $_imgDomain');
      
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
    }
  }

  /// 计算并填充 API 安全校验签名 Header
  /// 
  /// 签名规则符合荐片逆向标准：MD5("503" + timestamp + secret)
  Map<String, String> _signedHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'jianpian-linux/1.0',
    };
    if (_secret.isNotEmpty) {
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final sig = md5.convert(utf8.encode('503$ts$_secret')).toString();
      headers['version'] = '503';
      headers['timestamp'] = ts;
      headers['signature'] = sig;
    }
    return headers;
  }

  /// 底层通用的 HTTP GET 请求方法
  /// 
  /// 配备了网络超时延长（15秒）以及超时/网络异常自动重试逻辑（默认重试 2 次，每次间隔 1 秒）
  Future<dynamic> _get(String path, {int retries = 2}) async {
    int attempt = 0;
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

  /// 全局视频搜索接口
  /// 
  /// 关键词已进行 URL 安全编码，防御空格/特殊字符。返回搜索结果集及总数。
  Future<({List<VideoItem> videos, int total})> search(String keyword, {int page = 1}) async {
    final encodedKey = Uri.encodeComponent(keyword);
    final resp = await _get('/v2/search/videoV2?key=$encodedKey&page=$page');
    if (resp != null && resp['data'] != null && resp['data'] is List) {
      final videos = (resp['data'] as List).map((j) => VideoItem.fromSearchJson(j)).toList();
      final total = (resp['total'] as num?)?.toInt() ?? videos.length;
      return (videos: videos, total: total);
    }
    return (videos: <VideoItem>[], total: 0);
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
  /// 并发测试得出的延迟网速（毫秒），若超时通常置为 999999
  int? speedMs;
  /// 线路可用状态标志。若握手或视频流校验失败会置为 false
  bool usable = true;

  VideoSource({
    required this.name,
    required this.sourceName,
    required this.url,
    this.sourceConfigName = '',
    this.speedMs,
  });
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

  /// 解析普通视频的 source_list_source / vip_source_list_source 数组或短剧的 playlist
  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    final sources = <VideoSource>[];

    void appendSourceList(List? sourceList) {
      if (sourceList == null) return;
      for (final src in sourceList) {
        if (src is! Map) continue;
        final srcName = src['name']?.toString() ?? '';
        for (final item in (src['source_list'] as List? ?? [])) {
          if (item is! Map) continue;
          final url = item['url']?.toString() ?? '';
          if (url.isEmpty) continue;
          sources.add(VideoSource(
            name: srcName,
            sourceName: item['source_name']?.toString() ?? '',
            url: url,
            sourceConfigName: item['source_config_name']?.toString() ?? '',
          ));
        }
      }
    }

    // VIP 清晰度组优先，再合并常规 source_list_source（含 CDN 线路与高清组）
    appendSourceList(json['vip_source_list_source'] as List?);
    appendSourceList(json['source_list_source'] as List?);

    // 2. 短剧分类：从 playlist 数据节点进行适配解析
    final playlist = json['playlist'] as List?;
    if (playlist != null) {
      for (final item in playlist) {
        final lineName = item['source_config_name']?.toString() ?? '常规线路';
        final episodeTitle = item['title']?.toString() ?? '';
        final playUrl = item['url']?.toString() ?? '';
        sources.add(VideoSource(
          name: lineName,
          sourceName: episodeTitle,
          url: playUrl,
        ));
      }
    }

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
    final firstEpisode = sources.first.sourceName;
    final sameEp = sources.where((s) => s.sourceName == firstEpisode && s.usable);
    if (sameEp.isEmpty) return sources.first.url;
    return sameEp.first.url;
  }
}
