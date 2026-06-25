// lib/models/mubu_models.dart
// Unified data models for Mubu client
import '../utils/source_quality.dart';

/// Video item model
class VideoItem {
  final int id;
  final String title;
  final String coverPath;
  final String year;
  final String score;
  final String category;
  final int? lastPositionMs;
  final int? lastDurationMs;
  final String? lastEpisodeName;
  final String? lastLineName;
  final String description;

  VideoItem({
    required this.id,
    required this.title,
    this.coverPath = '',
    this.year = '',
    this.score = '',
    this.category = '',
    this.lastPositionMs,
    this.lastDurationMs,
    this.lastEpisodeName,
    this.lastLineName,
    this.description = '',
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
        id: json['id'] ?? 0,
        title: json['title'] ?? '',
        coverPath: json['coverPath'] ?? '',
        year: json['year'] ?? '',
        score: json['score'] ?? '',
        category: json['category'] ?? '',
        lastPositionMs: json['lastPositionMs'],
        lastDurationMs: json['lastDurationMs'],
        lastEpisodeName: json['lastEpisodeName'],
        lastLineName: json['lastLineName'],
        description: json['description'] ?? '',
      );

  factory VideoItem.fromSearchResult(SearchResult result) => VideoItem(
        id: result.id,
        title: result.title,
        coverPath: result.coverPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'coverPath': coverPath,
        'year': year,
        'score': score,
        'category': category,
        if (lastPositionMs != null) 'lastPositionMs': lastPositionMs,
        if (lastDurationMs != null) 'lastDurationMs': lastDurationMs,
        if (lastEpisodeName != null) 'lastEpisodeName': lastEpisodeName,
        if (lastLineName != null) 'lastLineName': lastLineName,
        if (description.isNotEmpty) 'description': description,
      };

  /// Build full cover URL based on image domain
  String coverUrl(String imgDomain) {
    if (coverPath.isEmpty) return '';
    var domain = imgDomain;
    if (domain == 'bqxqqqnf.top') domain = 'static2.gutaike.com';
    if (coverPath.startsWith('http')) {
      return coverPath.replaceAll('bqxqqqnf.top', 'static2.gutaike.com');
    }
    return 'https://$domain$coverPath';
  }

  bool get hasCover => coverPath.isNotEmpty;

  bool get isShortDrama => category == '短剧' || coverPath.toLowerCase().contains('short');
}

/// Search result model
class SearchResult {
  final int id;
  final String title;
  final String coverPath;

  SearchResult({required this.id, required this.title, required this.coverPath});

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        id: json['id'] ?? 0,
        title: json['title'] ?? '',
        coverPath: json['coverPath'] ?? '',
      );
}

/// Video source model
class VideoSource {
  final String name;
  final String sourceName;
  final String url;
  final String sourceConfigName;
  int? speedMs;
  bool usable;
  int? probeWidth;
  int? probeHeight;
  int? probeBitrateKbps;
  int? playlistMs;
  int? firstFrameMs;
  QualityTier? probedTier;

  VideoSource({
    required this.name,
    required this.sourceName,
    required this.url,
    this.sourceConfigName = '',
    this.speedMs,
    this.usable = true,
    this.probeWidth,
    this.probeHeight,
    this.probeBitrateKbps,
    this.playlistMs,
    this.firstFrameMs,
    this.probedTier,
  });

  void applyProbeMetrics({
    required bool usable,
    required int startupMs,
    int? playlistMs,
    int? probeWidth,
    int? probeHeight,
    int? probeBitrateKbps,
    int? firstFrameMs,
    QualityTier? probedTier,
  }) {
    this.usable = usable;
    speedMs = startupMs;
    if (usable) {
      this.playlistMs = playlistMs;
      this.probeWidth = probeWidth;
      this.probeHeight = probeHeight;
      this.probeBitrateKbps = probeBitrateKbps;
      this.firstFrameMs = firstFrameMs;
      this.probedTier = probedTier;
    } else {
      this.playlistMs = null;
      this.probeWidth = null;
      this.probeHeight = null;
      this.probeBitrateKbps = null;
      this.firstFrameMs = null;
      this.probedTier = null;
    }
  }

  void copyProbeFrom(VideoSource other) {
    usable = other.usable;
    speedMs = other.speedMs;
    playlistMs = other.playlistMs;
    probeWidth = other.probeWidth;
    probeHeight = other.probeHeight;
    probeBitrateKbps = other.probeBitrateKbps;
    firstFrameMs = other.firstFrameMs;
    probedTier = other.probedTier;
  }

  factory VideoSource.fromJson(Map<String, dynamic> json) => VideoSource(
        name: json['name'] ?? '',
        sourceName: json['source_name'] ?? '',
        url: json['url'] ?? '',
        sourceConfigName: json['source_config_name'] ?? json['sourceConfigName'] ?? '',
        speedMs: json['speedMs'] != null ? json['speedMs'] as int : null,
        usable: json['usable'] ?? true,
      );
}

/// Category item model
class CategoryItem {
  final int id;
  final String name;

  CategoryItem({required this.id, required this.name});

  factory CategoryItem.fromJson(Map<String, dynamic> json) => CategoryItem(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Tag item model
class TagItem {
  final int id;
  final String name;
  final int template;

  TagItem({required this.id, required this.name, this.template = 0});

  factory TagItem.fromJson(Map<String, dynamic> json) => TagItem(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
        template: json['template'] ?? 0,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'template': template};
}

/// Filter group model (for advanced filter UI)
/// Filter item model (for advanced filter UI)
class FilterItem {
  final String id;
  final String name;

  FilterItem({required this.id, required this.name});

  factory FilterItem.fromJson(Map<String, dynamic> json) => FilterItem(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Filter group model (for advanced filter UI)
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

/// Video detail model (expanded information)
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

  factory VideoDetail.fromJson(Map<String, dynamic> json) => VideoDetail(
        id: json['id'] ?? 0,
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        score: json['score'] ?? '',
        year: json['year'] ?? '',
        sources: (json['source_list_source'] as List? ?? [])
            .expand((src) => (src['source_list'] as List? ?? [])
                .map((item) => VideoSource(
                      name: src['name'] ?? '',
                      sourceName: item['source_name'] ?? '',
                      url: item['url'] ?? '',
                      sourceConfigName: item['source_config_name']?.toString() ?? '',
                    )))
            .toList(),
      );

  /// Pick the best available source URL
  String? get bestUrl {
    if (sources.isEmpty) return null;
    return sources.first.url;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'score': score,
        'year': year,
        'sources': sources
            .map((s) => {'name': s.name, 'source_name': s.sourceName, 'url': s.url})
            .toList(),
      };
}
