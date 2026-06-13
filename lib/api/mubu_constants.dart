// lib/api/mubu_constants.dart

import '../models/mubu_models.dart';

/// 将 filter key 映射到对应的 API 参数分类
enum FilterParam { type, area, year, sort, unknown }

class MubuConstants {
  // Load more / Pagination UI texts
  static const String loadMore = '加载更多';
  static const String reachedBottom = '—— 已经到底啦 ——';

  /// Helper to generate dynamic reached bottom text with video count
  static String reachedBottomWithCount(int count) {
    return '已经到底啦 ~ 共 $count 部影片';
  }

  /// 过滤掉特殊分类（推荐、netflix 等），只保留可用于筛选和导航的普通分类
  static List<CategoryItem> filterNavigableCategories(List<CategoryItem> cats) {
    return cats.where((c) =>
      c.name != '推荐' && c.id != 88 &&
      c.name.toLowerCase() != 'netflix' && c.id != 99
    ).toList();
  }

  /// 将 filter key 映射为人类可读的中文标签
  static String filterKeyLabel(String key) {
    final k = key.toLowerCase();
    if (k == 'type' || k == 'category_id') return '频道';
    if (k == 'area') return '地区';
    if (k == 'year') return '年份';
    if (k == 'sort') return '排序';
    return '筛选';
  }

  static FilterParam classifyFilterKey(String key) {
    final k = key.toLowerCase();
    if (k == 'type' || k == 'category_id') return FilterParam.type;
    if (k == 'area') return FilterParam.area;
    if (k == 'year') return FilterParam.year;
    if (k == 'sort') return FilterParam.sort;
    return FilterParam.unknown;
  }
}

