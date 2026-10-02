import '../models/mubu_models.dart';

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
