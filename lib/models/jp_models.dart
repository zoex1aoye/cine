class VideoItem {
  final int id;
  final String title;
  final String coverPath;
  final String year;
  final String score;
  final String category;

  VideoItem({
    required this.id,
    required this.title,
    this.coverPath = '',
    this.year = '',
    this.score = '',
    this.category = '',
  });

  factory VideoItem.fromTagJson(Map<String, dynamic> json) {
    final coverPath = (json['path'] ?? json['cover_image'] ?? json['cover'] ?? '').toString();
    
    final topCat = json['top_category'] as Map?;
    final resCats = json['res_categories'] as List? ?? [];
    final cats = json['categories'];
    
    bool isShortDrama = false;
    if (topCat != null && (topCat['id'] == 67 || topCat['id'] == '67' || topCat['name'] == '短剧')) {
      isShortDrama = true;
    } else if (resCats.any((c) => c is Map && (c['id'] == 67 || c['id'] == '67' || c['name'] == '短剧'))) {
      isShortDrama = true;
    } else if (cats is List && (cats.contains(67) || cats.contains('67'))) {
      isShortDrama = true;
    } else if (coverPath.contains('short')) {
      isShortDrama = true;
    }

    String category = '';
    if (isShortDrama) {
      category = '短剧';
    } else {
      category = topCat?['name']?.toString() ??
          (resCats.isNotEmpty ? (resCats[0]['name']?.toString() ?? '') : '');
    }

    return VideoItem(
      id: json['id'] ?? 0,
      title: json['title']?.toString() ?? '',
      coverPath: coverPath,
      category: category,
    );
  }

  factory VideoItem.fromSearchJson(Map<String, dynamic> json) {
    // Search API uses 'thumbnail' for the cover path (not 'cover' or 'path')
    final coverPath = (json['thumbnail'] ?? json['cover'] ?? json['path'] ?? json['cover_image'] ?? '').toString();

    // Year is nested: years: [{year: 2001}]
    final yearsList = json['years'] as List? ?? [];
    final year = yearsList.isNotEmpty
        ? (yearsList.first['year']?.toString() ?? '')
        : (json['year']?.toString() ?? '');

    // Category from top_category.name or res_categories[0].name
    final topCat = json['top_category'] as Map?;
    final resCats = json['res_categories'] as List? ?? [];
    final cats = json['categories'];

    bool isShortDrama = false;
    if (topCat != null && (topCat['id'] == 67 || topCat['id'] == '67' || topCat['name'] == '短剧')) {
      isShortDrama = true;
    } else if (resCats.any((c) => c is Map && (c['id'] == 67 || c['id'] == '67' || c['name'] == '短剧'))) {
      isShortDrama = true;
    } else if (cats is List && (cats.contains(67) || cats.contains('67'))) {
      isShortDrama = true;
    } else if (coverPath.contains('short')) {
      isShortDrama = true;
    }

    String category = '';
    if (isShortDrama) {
      category = '短剧';
    } else {
      category = topCat?['name']?.toString() ??
          (resCats.isNotEmpty ? (resCats[0]['name']?.toString() ?? '') : '');
    }

    return VideoItem(
      id: json['id'] ?? 0,
      title: json['title']?.toString() ?? '',
      coverPath: coverPath,
      year: year,
      score: json['score']?.toString() ?? '',
      category: category,
    );
  }

  String coverUrl(String imgDomain) {
    if (coverPath.isEmpty) return '';
    
    // Redirect failing bqxqqqnf.top domain to static2.gutaike.com
    String domain = imgDomain;
    if (domain == 'bqxqqqnf.top') {
      domain = 'static2.gutaike.com';
    }
    
    if (coverPath.startsWith('http')) {
      return coverPath.replaceAll('bqxqqqnf.top', 'static2.gutaike.com');
    }
    return 'https://$domain$coverPath';
  }

  bool get hasCover => coverPath.isNotEmpty;
}

class FilterItem {
  final String id;
  final String name;

  FilterItem({required this.id, required this.name});

  factory FilterItem.fromJson(Map<String, dynamic> json) => FilterItem(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class FilterGroup {
  final String key;
  final List<FilterItem> items;

  FilterGroup({required this.key, required this.items});

  factory FilterGroup.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List? ?? [];
    return FilterGroup(
      key: json['key'] ?? '',
      items: dataList.map((item) => FilterItem.fromJson(item)).toList(),
    );
  }

  String get displayName {
    switch (key) {
      case 'type':
        return '类型';
      case 'area':
        return '地区';
      case 'year':
        return '年份';
      case 'sort':
        return '排序';
      default:
        return key;
    }
  }
}
