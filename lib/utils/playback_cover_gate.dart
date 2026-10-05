import 'package:flutter/foundation.dart';

/// 播放页盖住下层时，受限档用来卸掉仍挂在树上的封面。
///
/// 深度计数：播放页 `acquire`，`dispose` 时 `release`。
/// 封面 Widget 听 [listenable]，被盖住时不再持有 `ImageStream`。
class PlaybackCoverGate {
  PlaybackCoverGate._();

  static final ValueNotifier<int> _depth = ValueNotifier<int>(0);

  static Listenable get listenable => _depth;

  static bool get isHeld => _depth.value > 0;

  static void acquire() {
    _depth.value++;
  }

  static void release() {
    if (_depth.value > 0) {
      _depth.value--;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _depth.value = 0;
  }
}
