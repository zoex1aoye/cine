/// 列表还没把窗口铺满时，是否再拉一页。
class ListViewportFill {
  /// 可滚距离不到视口的这个比例，就视为窗口还没被卡片铺满。
  static const fillFraction = 0.5;

  static bool needsAnotherPage({
    required bool busy,
    required bool hasMore,
    required int autoFills,
    required int maxAutoFills,
    required double maxScrollExtent,
    required double viewportDimension,
  }) {
    if (busy || !hasMore || autoFills >= maxAutoFills) return false;
    if (!maxScrollExtent.isFinite || maxScrollExtent < 0) return false;
    if (!viewportDimension.isFinite || viewportDimension <= 0) return true;
    // 底部「加载更多」会多出几十像素。只比一个固定小阈值，会把
    // 「卡片没铺满、但按钮已经让列表能滚一点」误判成已经铺满。
    return maxScrollExtent < viewportDimension * fillFraction;
  }
}
