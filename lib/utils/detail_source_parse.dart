/// Parsed playback source fields from detailv2 / short drama API JSON.
class DetailSourceFields {
  final String name;
  final String sourceName;
  final String url;
  final String sourceConfigName;
  final String weight;
  final int titlesDurationSec;
  final int trailerDurationSec;
  final int listOrder;
  final int? apiDurationSec;
  final bool usable;

  const DetailSourceFields({
    required this.name,
    required this.sourceName,
    required this.url,
    this.sourceConfigName = '',
    this.weight = '',
    this.titlesDurationSec = 0,
    this.trailerDurationSec = 0,
    this.listOrder = 0,
    this.apiDurationSec,
    this.usable = true,
  });
}

/// Only [source_list_source] + short [playlist]; skips VIP lists and duplicate URLs.
List<DetailSourceFields> parseDetailSources(Map<String, dynamic> json) {
  final sources = <DetailSourceFields>[];
  final seenUrls = <String>{};
  var listOrder = 0;

  final timeDataRaw = json['time_data'];
  final timeData = timeDataRaw is Map ? timeDataRaw : null;
  final videoDurationSec = timeData != null
      ? int.tryParse(timeData['total_duration']?.toString() ?? '')
      : null;

  void add({
    required String lineName,
    required Map item,
    required String url,
  }) {
    final weight = _weightFrom(item);
    final titles = _titlesFrom(item);
    final trailer = _trailerFrom(item);
    final sourceName = item['source_name']?.toString() ?? '';
    final configName = item['source_config_name']?.toString() ?? '';
    final apiDurationSec =
        int.tryParse(item['total_duration']?.toString() ?? '') ?? videoDurationSec;

    if (!url.startsWith('http')) {
      sources.add(DetailSourceFields(
        name: lineName,
        sourceName: sourceName,
        url: url,
        sourceConfigName: configName,
        weight: weight,
        titlesDurationSec: titles,
        trailerDurationSec: trailer,
        listOrder: listOrder++,
        apiDurationSec: apiDurationSec,
        usable: false,
      ));
      return;
    }
    if (seenUrls.contains(url)) return;
    seenUrls.add(url);
    sources.add(DetailSourceFields(
      name: lineName,
      sourceName: sourceName,
      url: url,
      sourceConfigName: configName,
      weight: weight,
      titlesDurationSec: titles,
      trailerDurationSec: trailer,
      listOrder: listOrder++,
      apiDurationSec: apiDurationSec,
    ));
  }

  for (final src in (json['source_list_source'] as List? ?? [])) {
    if (src is! Map) continue;
    final lineName = src['name']?.toString() ?? '';
    for (final item in (src['source_list'] as List? ?? [])) {
      if (item is! Map) continue;
      final url = item['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      add(lineName: lineName, item: item, url: url);
    }
  }

  for (final item in (json['playlist'] as List? ?? [])) {
    if (item is! Map) continue;
    final url = item['url']?.toString() ?? '';
    if (url.isEmpty) continue;
    add(
      lineName: item['source_config_name']?.toString() ?? '常规线路',
      item: {
        'source_name': item['title']?.toString() ?? '',
        'weight': item['weight'],
        'time_data': item['time_data'],
      },
      url: url,
    );
  }

  return sources;
}

String _weightFrom(Map item) {
  final w = item['weight'];
  if (w == null) return '';
  return w.toString().trim();
}

int _titlesFrom(Map item) {
  final td = item['time_data'];
  if (td is! Map) return 0;
  return int.tryParse(td['titles_duration']?.toString() ?? '') ?? 0;
}

int _trailerFrom(Map item) {
  final td = item['time_data'];
  if (td is! Map) return 0;
  return int.tryParse(td['trailer_duration']?.toString() ?? '') ?? 0;
}
