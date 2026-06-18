// lib/models/mubu_hive.dart
import 'package:hive/hive.dart';
import 'mubu_models.dart';

/// 节点测速记录
class NodeSpeedRecord {
  final String domainOrUrl;
  final int latencyMs;
  final int testedAtEpoch;

  NodeSpeedRecord({
    required this.domainOrUrl,
    required this.latencyMs,
    required this.testedAtEpoch,
  });
}

/// Adapter for NodeSpeedRecord (typeId: 2)
class NodeSpeedRecordAdapter extends TypeAdapter<NodeSpeedRecord> {
  @override
  final int typeId = 2;

  @override
  NodeSpeedRecord read(BinaryReader reader) {
    return NodeSpeedRecord(
      domainOrUrl: reader.readString(),
      latencyMs: reader.readInt(),
      testedAtEpoch: reader.readInt(),
    );
  }

  @override
  void write(BinaryWriter writer, NodeSpeedRecord obj) {
    writer.writeString(obj.domainOrUrl);
    writer.writeInt(obj.latencyMs);
    writer.writeInt(obj.testedAtEpoch);
  }
}

/// Adapter for VideoItem (typeId: 1)
class VideoItemAdapter extends TypeAdapter<VideoItem> {
  @override
  final int typeId = 1;

  @override
  VideoItem read(BinaryReader reader) {
    return VideoItem(
      id: reader.readInt(),
      title: reader.readString(),
      coverPath: reader.readString(),
      year: reader.readString(),
      score: reader.readString(),
      category: reader.readString(),
      lastPositionMs: reader.read() as int?,
      lastDurationMs: reader.read() as int?,
      lastEpisodeName: reader.read() as String?,
      lastLineName: reader.read() as String?,
      description: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, VideoItem obj) {
    writer.writeInt(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.coverPath);
    writer.writeString(obj.year);
    writer.writeString(obj.score);
    writer.writeString(obj.category);
    writer.write(obj.lastPositionMs);
    writer.write(obj.lastDurationMs);
    writer.write(obj.lastEpisodeName);
    writer.write(obj.lastLineName);
    writer.writeString(obj.description);
  }
}
