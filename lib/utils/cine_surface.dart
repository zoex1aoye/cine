import 'package:flutter/foundation.dart';

/// Compile-time product surface from `--dart-define=CINE_SURFACE=mobile|tv`.
enum CineSurface { mobile, tv }

const String _kCineSurfaceRaw = String.fromEnvironment(
  'CINE_SURFACE',
  defaultValue: 'mobile',
);

CineSurface? _debugOverrideSurface;

CineSurface get cineSurface =>
    _debugOverrideSurface ??
    (_kCineSurfaceRaw == 'tv' ? CineSurface.tv : CineSurface.mobile);

/// Test-only override. Production builds leave this null.
@visibleForTesting
bool? debugIsTvSurfaceOverride;

bool get isTvSurface =>
    debugIsTvSurfaceOverride ?? cineSurface == CineSurface.tv;

/// 详情页方向键走焦点遍历。仅内部全屏把方向键交给 seek / 音量。
bool tvTransportKeysEnabled(bool isFullscreen) => isTvSurface && isFullscreen;

/// 内部全屏路由还在栈顶时为 true。
///
/// Android 返回会先 pop 全屏路由，播放页若再 pop 一次就会直接离开播放页。
class TvFullscreenSignal {
  static int _depth = 0;

  static bool get active => _depth > 0;

  static void retain() => _depth++;

  static void release() {
    if (_depth > 0) _depth--;
  }

  @visibleForTesting
  static void debugReset() => _depth = 0;
}

@visibleForTesting
void debugOverrideSurface(CineSurface? surface) {
  _debugOverrideSurface = surface;
}

/// Debug helper: surface must match the Android flavor used at build time.
void assertSurfaceMatchesFlavorExpectation() {
  assert(() {
    debugPrint('CineSurface=$cineSurface (CINE_SURFACE=$_kCineSurfaceRaw)');
    return true;
  }());
}
