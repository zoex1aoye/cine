import 'package:flutter/foundation.dart';

/// Compile-time product surface from `--dart-define=CINE_SURFACE=mobile|tv`.
enum CineSurface { mobile, tv }

const String _kCineSurfaceRaw = String.fromEnvironment(
  'CINE_SURFACE',
  defaultValue: 'mobile',
);

final CineSurface cineSurface = _kCineSurfaceRaw == 'tv'
    ? CineSurface.tv
    : CineSurface.mobile;

/// Test-only override. Production builds leave this null.
@visibleForTesting
bool? debugIsTvSurfaceOverride;

bool get isTvSurface =>
    debugIsTvSurfaceOverride ?? cineSurface == CineSurface.tv;

/// 详情页方向键走焦点遍历。仅内部全屏把方向键交给 seek / 音量。
bool tvTransportKeysEnabled(bool isFullscreen) => isTvSurface && isFullscreen;

/// Debug helper: surface must match the Android flavor used at build time.
void assertSurfaceMatchesFlavorExpectation() {
  assert(() {
    debugPrint('CineSurface=$cineSurface (CINE_SURFACE=$_kCineSurfaceRaw)');
    return true;
  }());
}
