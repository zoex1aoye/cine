// lib/api/jp_api_impl.dart
import '../models/mubu_models.dart';
import '../api/mubu_api_client.dart' show MubuApiClient;
import 'jp_api.dart' show JpApi;

/// [MubuApiClient] 抽象层接口的原生实现类
/// 
/// 扮演适配器（Adapter）角色：负责将底层的 `JpApi` 服务与 `jp_models` 实体数据，
/// 映射转换至上层 UI 组件可以直接消费的 `mubu_models` 核心业务模型中。
class JpApiClientImpl implements MubuApiClient {
  // 核心底层 API 单例句柄
  final JpApi _jpApi = JpApi();

  @override
  String get baseUrl => _jpApi.baseUrl;

  @override
  String get imgDomain => _jpApi.imgDomain;

  @override
  Future<void> init() async {
    // 转发系统级初始化流程
    await _jpApi.init();
  }

  @override
  Future<List<CategoryItem>> getHomeCategorys() async {
    final list = await _jpApi.getHomeCategorys();
    return list
        .map((c) => CategoryItem(id: c.id, name: c.name))
        .toList();
  }

  @override
  Future<List<TagItem>> getHomeTags(int categoryId) async {
    final list = await _jpApi.getHomeTags(categoryId);
    return list
        .map((t) => TagItem(id: t.id, name: t.name, template: t.template))
        .toList();
  }

  @override
  Future<List<VideoItem>> getTagVideos(int tagId, {int tpl = 1, int page = 1, int count = 30}) async {
    final list = await _jpApi.getTagVideos(tagId, tpl: tpl, page: page, count: count);
    return list
        .map((v) => VideoItem(
              id: v.id,
              title: v.title,
              coverPath: v.coverPath,
              year: v.year,
              score: v.score,
              category: v.category,
            ))
        .toList();
  }

  @override
  Future<({List<VideoItem> videos, int total})> search(String keyword, {int page = 1}) async {
    final result = await _jpApi.search(keyword, page: page);
    final videos = result.videos.map((v) => VideoItem(
      id: v.id,
      title: v.title,
      coverPath: v.coverPath,
      year: v.year,
      score: v.score,
      category: v.category,
    )).toList();
    return (videos: videos, total: result.total);
  }

  @override
  Future<VideoDetail?> getVideoDetail(int id, {bool isShort = false}) async {
    // 针对短剧或常规影视进行路由分流详情查询
    final jd = await _jpApi.getVideoDetail(id, isShort: isShort);
    if (jd == null) return null;
    return VideoDetail(
      id: jd.id,
      title: jd.title,
      description: jd.description,
      score: jd.score,
      year: jd.year,
      sources: jd.sources
          .map((s) => VideoSource(
                name: s.name,
                sourceName: s.sourceName,
                url: s.url,
                speedMs: s.speedMs,
                usable: s.usable,
              ))
          .toList(),
    );
  }

  @override
  Future<List<FilterGroup>> getFilterOptions(int fcatePid) async {
    final legacyList = await _jpApi.getFilterOptions(fcatePid);
    return legacyList
        .map((g) => FilterGroup(
              key: g.key,
              items: g.items
                  .map((it) => FilterItem(id: it.id, name: it.name))
                  .toList(),
            ))
        .toList();
  }

  @override
  Future<List<VideoItem>> getFilteredVideos({
    required int fcatePid,
    String type = '',
    String area = '',
    String year = '',
    String sort = '',
    int page = 1,
  }) async {
    final list = await _jpApi.getFilteredVideos(
      fcatePid: fcatePid,
      type: type,
      area: area,
      year: year,
      sort: sort,
      page: page,
    );
    return list
        .map((v) => VideoItem(
              id: v.id,
              title: v.title,
              coverPath: v.coverPath,
              year: v.year,
              score: v.score,
              category: v.category,
            ))
        .toList();
  }

}
