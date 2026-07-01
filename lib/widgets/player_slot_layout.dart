import 'dart:ui';

/// Fixed outer slot + inner video viewport metrics for the player detail page.
abstract final class PlayerSlotLayout {
  static const movieMaxHeightFraction = 0.42;
  static const shortDramaMaxHeightFraction = 0.65;
  static const maxInnerAspectRatio = 2.39;
  static const probeDecodeDriftThreshold = 0.05;
  static const innerRatioAnimMs = 200;

  /// Outer slot height (fixed for the page session at a given content width).
  static double slotHeight({
    required double width,
    required bool isShortDrama,
    required double screenHeight,
  }) {
    final natural = isShortDrama ? width * 16 / 9 : width * 9 / 16;
    final cap = screenHeight *
        (isShortDrama ? shortDramaMaxHeightFraction : movieMaxHeightFraction);
    return natural > cap ? cap : natural;
  }

  static double defaultInnerAspectRatio({required bool isShortDrama}) =>
      isShortDrama ? 9 / 16 : 16 / 9;

  static double normalizeAspectRatio(double ratio) {
    if (ratio <= 0) return 16 / 9;
    return ratio > maxInnerAspectRatio ? maxInnerAspectRatio : ratio;
  }

  static double aspectRatioFromProbe(
    int? width,
    int? height, {
    required bool isShortDrama,
  }) {
    if (width != null && height != null && width > 0 && height > 0) {
      return normalizeAspectRatio(width / height);
    }
    return defaultInnerAspectRatio(isShortDrama: isShortDrama);
  }

  static bool shouldReplaceInnerRatio(
    double current,
    double next, {
    required bool isShortDrama,
  }) {
    if ((next - current).abs() < 0.001) return false;
    final initial = defaultInnerAspectRatio(isShortDrama: isShortDrama);
    if ((current - initial).abs() < 0.001) return true;
    return (next - current).abs() / current > probeDecodeDriftThreshold;
  }

  /// [BoxFit.contain] rectangle for [innerAspect] inside the slot.
  static Size innerVideoSize(
    double slotWidth,
    double slotHeight,
    double innerAspect,
  ) {
    if (slotWidth <= 0 || slotHeight <= 0) return Size.zero;
    final slotAspect = slotWidth / slotHeight;
    if (slotAspect > innerAspect) {
      final h = slotHeight;
      return Size(h * innerAspect, h);
    }
    final w = slotWidth;
    return Size(w, w / innerAspect);
  }
}
