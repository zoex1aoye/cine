import 'dart:math' as math;

/// Loading HUD + play-button sizes scaled to the player slot and screen tier.
abstract final class PlayerOverlayMetrics {
  static (double min, double max) _outerBounds(double screenWidth) {
    return switch (screenWidth) {
      < 500 => (72.0, 108.0), // phone portrait
      < 900 => (56.0, 96.0), // phone landscape — short slot height
      < 1200 => (80.0, 132.0), // tablet
      < 1600 => (96.0, 156.0), // laptop
      < 2400 => (112.0, 196.0), // desktop / small 4K
      < 4320 => (128.0, 220.0), // 65" 4K UHD
      _ => (144.0, 248.0), // 8K TV
    };
  }

  static (double min, double max) _playCoreBounds(double screenWidth) {
    return switch (screenWidth) {
      < 500 => (52.0, 72.0),
      < 900 => (44.0, 64.0),
      < 1200 => (56.0, 80.0),
      < 1600 => (64.0, 92.0),
      < 2400 => (76.0, 108.0),
      < 4320 => (88.0, 120.0),
      _ => (96.0, 132.0),
    };
  }

  /// Diameter of the loading HUD circle, derived from slot short side.
  static ({
    double outerDiameter,
    double ringDiameter,
    double strokeWidth,
    double fontSize,
    double glowBlur,
  }) loadingHud({
    required double slotWidth,
    required double slotHeight,
    required double screenWidth,
  }) {
    final shortSide = math.min(
      slotWidth > 0 ? slotWidth : screenWidth,
      slotHeight > 0 ? slotHeight : screenWidth * 0.42,
    );
    final (minOuter, maxOuter) = _outerBounds(screenWidth);
    final outer = (shortSide * 0.46).clamp(minOuter, maxOuter);
    final ring = outer * 0.68;
    final stroke = outer < 90 ? 2.5 : (outer < 150 ? 3.0 : 4.0);
    final font = (outer * 0.21).clamp(16.0, maxOuter * 0.24);
    final glow = outer * 0.12;

    return (
      outerDiameter: outer,
      ringDiameter: ring,
      strokeWidth: stroke,
      fontSize: font,
      glowBlur: glow,
    );
  }

  /// Play-button overlay sizing for the same slot.
  static ({
    double coreSize,
    double iconSize,
    double pulseRange,
    double pulseRange2,
  }) playButton({
    required double slotWidth,
    required double slotHeight,
    required double screenWidth,
  }) {
    final shortSide = math.min(
      slotWidth > 0 ? slotWidth : screenWidth,
      slotHeight > 0 ? slotHeight : screenWidth * 0.42,
    );
    final (minCore, maxCore) = _playCoreBounds(screenWidth);
    final core = (shortSide * 0.26).clamp(minCore, maxCore);
    final icon = core * 0.56;
    final pulse = core * 0.42;
    final pulse2 = core * 0.22;

    return (
      coreSize: core,
      iconSize: icon,
      pulseRange: pulse,
      pulseRange2: pulse2,
    );
  }
}
