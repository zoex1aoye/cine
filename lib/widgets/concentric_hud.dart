// lib/widgets/concentric_hud.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/mubu_models.dart';
import '../api/mubu_ui_adapt.dart';

/// 同心雷达/测速加载指示器 (ConcentricHud)
/// 
/// 用于展示播放源测速的进度、雷达扫掠/打点动画。
/// 已重构为 [StatefulWidget]，配备了与播放按钮风格一致的呼吸光晕与脉冲光环动效。
class ConcentricHud extends StatefulWidget {
  /// 当前整体测速进度 (0.0 - 1.0)
  final double progress;
  /// 全部待测视频源列表
  final List<VideoSource> sources;
  /// 参与本次测速的索引集合
  final List<int> indicesToTest;

  const ConcentricHud({
    Key? key,
    required this.progress,
    required this.sources,
    required this.indicesToTest,
  }) : super(key: key);

  @override
  State<ConcentricHud> createState() => _ConcentricHudState();
}

class _ConcentricHudState extends State<ConcentricHud> with SingleTickerProviderStateMixin {
  // 呼吸动画控制器，负责呼吸光环和阴影光晕的缩放与淡入淡出效果
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 动画周期 1.8 秒，无限循环播放
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 根据延迟毫秒数返回对应的网速指示颜色
  Color _speedColor(int? ms) {
    if (ms == null) return Colors.white24;
    if (ms >= 999999) return Colors.redAccent;
    if (ms < 300) return Colors.green;
    if (ms < 800) return Colors.orange;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.indicesToTest.length;
    final isRadarMode = n > 16;
    final displayPercent = (widget.progress * 100).toInt();

    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final val = _controller.value;
          final baseWidth = UIAdapt.px(context, 200);
          final baseHeight = UIAdapt.px(context, 200);

          return Stack(
            alignment: Alignment.center,
            children: [
              // 呼吸脉冲光环 2 (最外层，范围稍大，渐变消失)
              Container(
                width: baseWidth + UIAdapt.px(context, 80) * val,
                height: baseHeight + UIAdapt.px(context, 80) * val,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE50914).withOpacity(0.12 * (1.0 - val)),
                ),
              ),
              // 呼吸脉冲光环 1 (中层，范围稍小，渐变消失)
              Container(
                width: baseWidth + UIAdapt.px(context, 40) * val,
                height: baseHeight + UIAdapt.px(context, 40) * val,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE50914).withOpacity(0.25 * (1.0 - val)),
                ),
              ),
              // 主同心 HUD 容器，支持呼吸投影光晕
              Container(
                width: baseWidth,
                height: baseHeight,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0C0C0E).withAlpha(150),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withOpacity(0.3 + 0.2 * (1.0 - val)),
                      blurRadius: UIAdapt.px(context, 30 + 15 * val),
                      spreadRadius: UIAdapt.px(context, 3 + 3 * val),
                    )
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 内层：同心进度环
                    SizedBox(
                      width: UIAdapt.px(context, 130),
                      height: UIAdapt.px(context, 130),
                      child: CircularProgressIndicator(
                        value: widget.progress,
                        strokeWidth: UIAdapt.px(context, 4),
                        backgroundColor: Colors.white.withAlpha(10),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                      ),
                    ),
                    // Outer dynamic track (Radar Sweep or Circular Dots)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _OuterTrackPainter(
                          progress: widget.progress,
                          sources: widget.sources,
                          indicesToTest: widget.indicesToTest,
                          isRadarMode: isRadarMode,
                          speedColorFunc: _speedColor,
                        ),
                      ),
                    ),
                    // Center percentage
                    Text(
                      '$displayPercent%',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: UIAdapt.fontSize(context, 32),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OuterTrackPainter extends CustomPainter {
  final double progress;
  final List<VideoSource> sources;
  final List<int> indicesToTest;
  final bool isRadarMode;
  final Color Function(int?) speedColorFunc;

  _OuterTrackPainter({
    required this.progress,
    required this.sources,
    required this.indicesToTest,
    required this.isRadarMode,
    required this.speedColorFunc,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 16; // Outer ring radius

    if (isRadarMode) {
      // RADAR SCANNING MODE (N > 16)
      // Base faint track
      final basePaint = Paint()
        ..color = Colors.white.withAlpha(8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, basePaint);

      // We draw the progress dashed track
      final double startAngle = -math.pi / 2;
      final double totalSweep = progress * 2 * math.pi;

      // Draw dashed arcs with colors based on angle
      _drawRadarDashedArcs(canvas, center, radius, startAngle, totalSweep);

      // Scanning tip dot with glowing effect
      if (progress > 0) {
        final tipAngle = startAngle + totalSweep;
        final tipX = center.dx + radius * math.cos(tipAngle);
        final tipY = center.dy + radius * math.sin(tipAngle);
        final tipOffset = Offset(tipX, tipY);

        final glowPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tipOffset, 4, glowPaint);

        final outerGlowPaint = Paint()
          ..color = Colors.white.withAlpha(100)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tipOffset, 8, outerGlowPaint);
      }
    } else {
      // CIRCULAR DOTS MODE (N <= 16)
      final n = indicesToTest.length;
      if (n == 0) return;

      for (int i = 0; i < n; i++) {
        // Dot position
        final angle = (i * (360 / n) - 90) * math.pi / 180;
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        final dotOffset = Offset(x, y);

        // Fetch latency
        final sourceIdx = indicesToTest[i];
        final source = sources[sourceIdx];

        Color dotColor;
        double dotRadius = 4.0;
        bool isTested = source.speedMs != null;

        if (isTested) {
          dotColor = speedColorFunc(source.speedMs);
          if (dotColor != Colors.white24) {
            // Glow effect for active dots
            final glowPaint = Paint()
              ..color = dotColor.withAlpha(80)
              ..style = PaintingStyle.fill;
            canvas.drawCircle(dotOffset, dotRadius + 3, glowPaint);
          }
        } else {
          dotColor = Colors.white.withAlpha(20);
        }

        final dotPaint = Paint()
          ..color = dotColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(dotOffset, dotRadius, dotPaint);
      }
    }
  }

  void _drawRadarDashedArcs(Canvas canvas, Offset center, double radius, double startAngle, double sweepAngle) {
    const double dashLen = 4.0;
    const double gapLen = 4.0;

    // Segment 1 (Green) corresponds to 0% to 60% of progress
    // Segment 2 (Orange) corresponds to 60% to 85% of progress
    // Segment 3 (Red) corresponds to 85% to 100% of progress
    final double greenLimit = 0.6 * 2 * math.pi;
    final double orangeLimit = 0.85 * 2 * math.pi;

    double currentSweep = 0.0;
    while (currentSweep < sweepAngle) {
      double arcStart = startAngle + currentSweep;
      double arcSweep = dashLen / radius;
      if (currentSweep + arcSweep > sweepAngle) {
        arcSweep = sweepAngle - currentSweep;
      }

      // Determine color based on current angle position
      Color color = Colors.green;
      if (currentSweep >= orangeLimit) {
        color = Colors.redAccent;
      } else if (currentSweep >= greenLimit) {
        color = Colors.orange;
      }

      final arcPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        arcStart,
        arcSweep,
        false,
        arcPaint,
      );

      currentSweep += (dashLen + gapLen) / radius;
    }
  }

  @override
  bool shouldRepaint(covariant _OuterTrackPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.sources != sources ||
        oldDelegate.indicesToTest != indicesToTest;
  }
}
