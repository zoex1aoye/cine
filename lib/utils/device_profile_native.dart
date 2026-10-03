import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'device_budget.dart';

export 'device_budget.dart';

/// 运行时设备能力画像（Android 经 MethodChannel 读内存；其他平台保持 normal）。
class DeviceProfile {
  DeviceProfile._();

  static const _channel = MethodChannel('com.example.cine/device');

  static DeviceProfileTier _tier = DeviceProfileTier.normal;
  static bool _initialized = false;
  static int? _totalMemBytes;
  static int? _availMemBytes;

  static DeviceProfileTier get tier => _tier;
  static bool get isConstrained => _tier != DeviceProfileTier.normal;
  static bool get isUltra => _tier == DeviceProfileTier.ultra;
  static DeviceBudget get budget => DeviceBudget.of(_tier);
  static int? get totalMemBytes => _totalMemBytes;
  static int? get availMemBytes => _availMemBytes;

  /// 受限档下首屏测速的并行批大小。
  static const constrainedProbeEarlyBatch = 2;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final raw =
          await _channel.invokeMapMethod<String, dynamic>('getMemoryInfo');
      if (raw != null) {
        _totalMemBytes = (raw['totalMem'] as num?)?.toInt();
        _availMemBytes = (raw['availMem'] as num?)?.toInt();
        _tier = DeviceBudget.tierFor(
          totalMemBytes: _totalMemBytes,
          lowRam: raw['lowRam'] as bool? ?? false,
        );
      }
    } catch (_) {
      // Channel missing (desktop / stub activity) → keep normal.
    }
  }

  static void applyImageCacheLimits() {
    if (!isConstrained) return;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = budget.imageCacheCount;
    cache.maximumSizeBytes = budget.imageCacheBytes;
  }

  /// 进入播放页时释放首页不再展示的封面，给视频解码留物理内存。
  ///
  /// 只做 `clear()`：它驱逐未被任何 Widget 引用的缓存项；仍在屏幕下层显示的
  /// 封面是 live image，不受影响，返回首页不会整屏重解码。
  /// 不用 `clearLiveImages()`——Flutter 文档明确它不会缓解内存压力，反而会让
  /// 仍在使用的图片失去缓存追踪。
  static void trimImageCacheOnPlayerEnter() {
    if (!isConstrained) return;
    PaintingBinding.instance.imageCache.clear();
  }

  @visibleForTesting
  static void debugOverride({
    DeviceProfileTier? tier,
    int? totalMemBytes,
    bool resetInitialized = false,
  }) {
    if (resetInitialized) _initialized = false;
    if (tier != null) _tier = tier;
    if (totalMemBytes != null) _totalMemBytes = totalMemBytes;
  }
}
