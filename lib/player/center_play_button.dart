/// 播放器中心播停圆键尺寸。跟播放器短边走，不跟屏幕宽。
class CenterPlayButtonMetrics {
  /// 常见窗口槽高度附近；此短边保持改前的 48 / 16。
  static const referenceShortestSide = 360.0;
  static const referenceIcon = 48.0;
  static const referencePadding = 16.0;

  /// 极小窗仍能点到；极大窗（含内部全屏）不把画面中心占满。
  static const minScale = 0.45;
  static const maxScale = 2.2;

  final double icon;
  final double padding;

  const CenterPlayButtonMetrics({required this.icon, required this.padding});

  double get scale => icon / referenceIcon;

  double get diameter => icon + padding * 2;

  static CenterPlayButtonMetrics forShortestSide(double shortestSide) {
    final side =
        shortestSide.isFinite && shortestSide > 0
            ? shortestSide
            : referenceShortestSide;
    final factor = (side / referenceShortestSide).clamp(minScale, maxScale);
    return CenterPlayButtonMetrics(
      icon: referenceIcon * factor,
      padding: referencePadding * factor,
    );
  }

  /// [width] / [height] 来自播放器控件区域。无界或非正时退回基准尺寸。
  static CenterPlayButtonMetrics forPlayer(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return forShortestSide(referenceShortestSide);
    }
    final shortest = width < height ? width : height;
    return forShortestSide(shortest);
  }
}
