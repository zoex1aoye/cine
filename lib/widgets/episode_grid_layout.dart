/// Responsive episode/version grid metrics for phone → 4K TV.
abstract final class EpisodeGridLayout {
  static const gridSpacing = 8.0;

  /// Target tile width by screen tier (aligned with [MovieSliverGrid] breakpoints).
  static double targetCellWidth(double screenWidth) {
    if (screenWidth < 500) return 100;
    if (screenWidth < 900) return 118;
    if (screenWidth < 1200) return 136;
    if (screenWidth < 1600) return 168;
    if (screenWidth < 2400) return 200;
    return 228;
  }

  /// Target tile height — scales for tablet/desktop/TV viewing distance.
  static double targetCellHeight(
    double screenWidth, {
    required bool hasLongLabel,
  }) {
    final base = switch (screenWidth) {
      < 500 => 50.0,
      < 900 => 54.0,
      < 1200 => 58.0,
      < 1600 => 64.0,
      < 2400 => 72.0,
      _ => 84.0,
    };
    return hasLongLabel ? base + 6 : base;
  }

  static double spacingFor(double screenWidth) {
    if (screenWidth < 1600) return gridSpacing;
    if (screenWidth < 2400) return gridSpacing * 1.25;
    return gridSpacing * 1.5;
  }

  static int maxColumns(double screenWidth) {
    if (screenWidth < 500) return 4;
    if (screenWidth < 900) return 5;
    if (screenWidth < 1200) return 6;
    if (screenWidth < 1600) return 7;
    if (screenWidth < 2400) return 9;
    return 10;
  }

  /// Movie versions / few episodes use fewer, wider columns.
  static int minColumns(double screenWidth, {required bool compact}) {
    if (!compact) return 3;
    if (screenWidth < 500) return 2;
    if (screenWidth < 1200) return 2;
    return 3;
  }

  static ({
    int crossAxisCount,
    double childAspectRatio,
    double spacing,
  }) metrics({
    required double panelWidth,
    required double screenWidth,
    required int itemCount,
    required bool hasLongLabel,
  }) {
    if (panelWidth <= 0) {
      return (
        crossAxisCount: 2,
        childAspectRatio: 2.0,
        spacing: gridSpacing,
      );
    }

    final compact = hasLongLabel || itemCount <= 8;
    final spacing = spacingFor(screenWidth);
    final cellW = targetCellWidth(screenWidth);
    final cellH = targetCellHeight(screenWidth, hasLongLabel: hasLongLabel);
    final maxCols = maxColumns(screenWidth);
    final minCols = minColumns(screenWidth, compact: compact);

    var cols = ((panelWidth + spacing) / (cellW + spacing)).floor();
    cols = cols.clamp(minCols, maxCols);

    if (compact && itemCount > 0 && itemCount < cols) {
      cols = itemCount.clamp(minCols, cols);
    }

    final actualCellW = (panelWidth - (cols - 1) * spacing) / cols;
    final aspectRatio = actualCellW / cellH;

    return (
      crossAxisCount: cols,
      childAspectRatio: aspectRatio,
      spacing: spacing,
    );
  }
}
