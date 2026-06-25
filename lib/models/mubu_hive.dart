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

/// Per-line stream probe cache (video + line name).
class SourceProbeRecord {
  final String probeUrl;
  final bool usable;
  final int latencyMs;
  final int width;
  final int height;
  final int bitrateKbps;
  final int firstFrameMs;
  final int effectiveTierIndex;
  final int testedAtEpoch;

  SourceProbeRecord({
    required this.probeUrl,
    required this.usable,
    required this.latencyMs,
    this.width = 0,
    this.height = 0,
    this.bitrateKbps = 0,
    this.firstFrameMs = 0,
    this.effectiveTierIndex = 0,
    required this.testedAtEpoch,
  });
}

class SourceProbeRecordAdapter extends TypeAdapter<SourceProbeRecord> {
  @override
  final int typeId = 3;

  @override
  SourceProbeRecord read(BinaryReader reader) {
    return SourceProbeRecord(
      probeUrl: reader.readString(),
      usable: reader.readBool(),
      latencyMs: reader.readInt(),
      width: reader.readInt(),
      height: reader.readInt(),
      bitrateKbps: reader.readInt(),
      firstFrameMs: reader.readInt(),
      effectiveTierIndex: reader.readInt(),
      testedAtEpoch: reader.readInt(),
    );
  }

  @override
  void write(BinaryWriter writer, SourceProbeRecord obj) {
    writer.writeString(obj.probeUrl);
    writer.writeBool(obj.usable);
    writer.writeInt(obj.latencyMs);
    writer.writeInt(obj.width);
    writer.writeInt(obj.height);
    writer.writeInt(obj.bitrateKbps);
    writer.writeInt(obj.firstFrameMs);
    writer.writeInt(obj.effectiveTierIndex);
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
