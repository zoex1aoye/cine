// lib/api/mubu_constants.dart

class MubuConstants {
  // Load more / Pagination UI texts
  static const String loadMore = '加载更多';
  static const String reachedBottom = '—— 已经到底啦 ——';

  /// Helper to generate dynamic reached bottom text with video count
  static String reachedBottomWithCount(int count) {
    return '已经到底啦 ~ 共 $count 部影片';
  }
}
