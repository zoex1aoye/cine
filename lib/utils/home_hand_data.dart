import '../models/mubu_models.dart';

/// 首页一个分类下的板块封面数据。
///
/// 板块列表可以先于手推数据到达；手推晚到时只重算已经回来的板块。
class HomeTagFeed {
  HomeTagFeed({required this.count});

  final int count;
  final Map<int, List<VideoItem>> _raw = {};
  Map<int, List<VideoItem>> _hand = const {};
  bool _handReady = false;

  void setRaw(int tagId, List<VideoItem> videos) {
    _raw[tagId] = videos;
  }

  void setHand(Map<int, List<VideoItem>> hand) {
    _hand = hand;
    _handReady = true;
  }

  bool hasRaw(int tagId) => _raw.containsKey(tagId);

  List<VideoItem>? videosFor(int tagId) {
    final raw = _raw[tagId];
    if (raw == null) return null;
    return mergeHomeHandFirstPage(
      tagId: tagId,
      page: 1,
      count: count,
      tplVideos: raw,
      handData: _handReady ? _hand : const {},
    );
  }
}

/// 官方 Category 第 1 页：hand_data 前置到 tpl 列表，截到 [count]。
List<VideoItem> mergeHomeHandFirstPage({
  required int tagId,
  required int page,
  required int count,
  required List<VideoItem> tplVideos,
  required Map<int, List<VideoItem>> handData,
}) {
  if (page != 1 || count <= 0) return tplVideos;
  final extra = handData[tagId];
  if (extra == null || extra.isEmpty) return tplVideos;

  final seen = <int>{};
  final out = <VideoItem>[];
  for (final v in [...extra, ...tplVideos]) {
    if (v.id == 0 || !seen.add(v.id)) continue;
    out.add(v);
    if (out.length >= count) break;
  }
  return out;
}
