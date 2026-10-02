// lib/api/mubu_api_client.dart
// Abstract API client for Mubu client

import '../models/mubu_models.dart';

abstract class MubuApiClient {
  static late final MubuApiClient instance;

  String get baseUrl;
  String get imgDomain;

  /// 封面换域候选（主域置首，含 package + 硬编码备份）。
  List<String> get imgDomainCandidates;

  Future<void> init();
  Future<List<CategoryItem>> getHomeCategorys();
  Future<List<TagItem>> getHomeTags(int categoryId);
  Future<List<VideoItem>> getTagVideos(int tagId, {int tpl = 1, int page = 1, int count = 30});
  Future<Map<int, List<VideoItem>>> getHomeHandData(int categoryId);
  Future<({List<VideoItem> videos, int total})> search(String keyword, {int page = 1});
  Future<VideoDetail?> getVideoDetail(int id, {bool isShort = false});
  Future<List<FilterGroup>> getFilterOptions(int fcatePid);
  Future<List<VideoItem>> getFilteredVideos({
    required int fcatePid,
    String type = '',
    String area = '',
    String year = '',
    String sort = '',
    int page = 1,
  });
}
