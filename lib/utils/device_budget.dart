/// 设备能力分档（与 CineSurface 无关，只看内存）。
enum DeviceProfileTier { normal, constrained, ultra }

/// 各档位的内存预算。纯数据，native / stub 共用，避免两份常量漂移。
class DeviceBudget {
  const DeviceBudget({
    required this.demuxFwdBytes,
    required this.demuxBackBytes,
    required this.readaheadSecs,
    required this.cacheSecs,
    required this.streamBuffer,
    required this.hwdecExtraFrames,
    required this.imageCacheCount,
    required this.imageCacheBytes,
    required this.coverDecodeMaxWidth,
  });

  /// mpv 属性值（字符串）。
  final String demuxFwdBytes;
  final String demuxBackBytes;
  final String readaheadSecs;
  final String cacheSecs;
  final String streamBuffer;
  final String hwdecExtraFrames;

  /// Flutter ImageCache 上限。封面已按 memCacheWidth 缩小，字节数才是真正的预算。
  final int imageCacheCount;
  final int imageCacheBytes;

  /// 封面解码宽度上限（物理像素）。
  final int coverDecodeMaxWidth;

  /// 常规设备：不收紧。
  static const normal = DeviceBudget(
    demuxFwdBytes: '33554432',
    demuxBackBytes: '25165824',
    readaheadSecs: '25',
    cacheSecs: '45',
    streamBuffer: '1048576',
    hwdecExtraFrames: '4',
    imageCacheCount: 1000,
    imageCacheBytes: 100 << 20,
    coverDecodeMaxWidth: 720,
  );

  /// 内存 < 2GiB 的设备（含标称 2GB 的低端手机/盒子）。
  static const constrained = DeviceBudget(
    demuxFwdBytes: '10485760', // 10 MB
    demuxBackBytes: '6291456', // 6 MB
    readaheadSecs: '12',
    cacheSecs: '20',
    streamBuffer: '524288', // 512 KB
    hwdecExtraFrames: '2',
    imageCacheCount: 100,
    imageCacheBytes: 48 << 20,
    coverDecodeMaxWidth: 240,
  );

  /// 1GB 级（totalMem <= 1.2GB 或系统标记 low-ram）。
  /// 后向缓冲保留 4MB：按 5–8Mbps 约 4–6 秒，再小则 TV 快退 10 秒必然回源。
  static const ultra = DeviceBudget(
    demuxFwdBytes: '8388608', // 8 MB
    demuxBackBytes: '4194304', // 4 MB
    readaheadSecs: '10',
    cacheSecs: '15',
    streamBuffer: '262144', // 256 KB
    hwdecExtraFrames: '1',
    imageCacheCount: 100,
    imageCacheBytes: 24 << 20,
    coverDecodeMaxWidth: 180,
  );

  /// 封面 memCacheWidth（物理像素）：布局宽 × dpr，夹在 [64, coverDecodeMaxWidth]。
  int coverDecodeWidth({required double logicalWidth, required double dpr}) {
    if (!logicalWidth.isFinite || dpr <= 0) return coverDecodeMaxWidth;
    return (logicalWidth * dpr).round().clamp(64, coverDecodeMaxWidth);
  }

  static DeviceBudget of(DeviceProfileTier tier) {
    switch (tier) {
      case DeviceProfileTier.normal:
        return normal;
      case DeviceProfileTier.constrained:
        return constrained;
      case DeviceProfileTier.ultra:
        return ultra;
    }
  }

  /// totalMem <= 1.2GiB 视为 ultra。
  static const ultraMaxTotalMem = 1288490188;

  /// totalMem < 2GiB 视为 constrained（标称 2GB 的设备实际上报约 1.9GiB）。
  static const constrainedMaxTotalMem = 2 << 30;

  /// 由内存与系统 low-ram 标记推导档位。
  /// 读不到内存信息时只看 [lowRam]，都没有则按 normal。
  static DeviceProfileTier tierFor({int? totalMemBytes, bool lowRam = false}) {
    final total = totalMemBytes;
    final known = total != null && total > 0;
    if (known && total <= ultraMaxTotalMem) return DeviceProfileTier.ultra;
    if (lowRam) return DeviceProfileTier.ultra;
    if (known && total < constrainedMaxTotalMem) {
      return DeviceProfileTier.constrained;
    }
    return DeviceProfileTier.normal;
  }
}
