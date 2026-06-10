// lib/api/mubu_ui_adapt.dart
import 'package:flutter/material.dart';

class UIAdapt {
  /// Calculate the global scale factor based on screen width
  static double scale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 1200) return 1.0;
    return (width / 1400).clamp(1.0, 2.0);
  }

  /// Scale a layout coordinate value (pixels, dimensions, etc.)
  static double px(BuildContext context, double value) {
    return value * scale(context);
  }

  /// Scale a font size
  static double fontSize(BuildContext context, double value) {
    return value * scale(context);
  }
}
