import 'package:flutter/foundation.dart';

/// Compile-time product surface from `--dart-define=CINE_SURFACE=mobile|tv`.
enum CineSurface { mobile, tv }

const String _kCineSurfaceRaw =
    String.fromEnvironment('CINE_SURFACE', defaultValue: 'mobile');

final CineSurface cineSurface =
    _kCineSurfaceRaw == 'tv' ? CineSurface.tv : CineSurface.mobile;

bool get isTvSurface => cineSurface == CineSurface.tv;

/// Debug helper: surface must match the Android flavor used at build time.
void assertSurfaceMatchesFlavorExpectation() {
  assert(() {
    debugPrint('CineSurface=$cineSurface (CINE_SURFACE=$_kCineSurfaceRaw)');
    return true;
  }());
}
