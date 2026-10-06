import 'list_viewport_fill.dart';

/// 搜索列表是否还要再翻一页才能铺满窗口。
///
/// `/v2/search/videoV2` 忽略 `count`，每页固定 10 条；`total` 才是总条数。
/// 不能把单次条数加大（加了也不生效）。某一页 0 条就停，避免 `total` 偏大时一直请求。
class SearchViewportFill {
  /// 首屏加上这几次自动翻页。每页只有 10 条，所以上限比「查看全部」高；铺满即停。
  static const maxAutoFills = 6;

  static bool hasMore({
    required int loadedCount,
    required int total,
    required int latestPageCount,
  }) {
    if (latestPageCount <= 0 || total <= 0) return false;
    return loadedCount < total;
  }

  static bool needsAnotherPage({
    required bool busy,
    required bool hasMore,
    required int autoFills,
    required double maxScrollExtent,
    required double viewportDimension,
  }) {
    return ListViewportFill.needsAnotherPage(
      busy: busy,
      hasMore: hasMore,
      autoFills: autoFills,
      maxAutoFills: maxAutoFills,
      maxScrollExtent: maxScrollExtent,
      viewportDimension: viewportDimension,
    );
  }
}
