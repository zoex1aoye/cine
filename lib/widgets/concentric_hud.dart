// lib/widgets/concentric_hud.dart
import 'package:flutter/material.dart';
import '../models/mubu_models.dart';
import 'player_overlay_metrics.dart';

/// 轻量化加载指示器 (ConcentricHud)
///
/// 尺寸按播放器槽位短边 + 屏幕档位缩放，横屏手机不再误用桌面大号 HUD。
class ConcentricHud extends StatefulWidget {
  /// 当前整体测速进度 (0.0 - 1.0)
  final double progress;
  /// 全部待测视频源列表
  final List<VideoSource> sources;
  /// 参与本次测速的索引集合
  final List<int> indicesToTest;

  const ConcentricHud({
    super.key,
    required this.progress,
    required this.sources,
    required this.indicesToTest,
  });

  @override
  State<ConcentricHud> createState() => _ConcentricHudState();
}

class _ConcentricHudState extends State<ConcentricHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return LayoutBuilder(
      builder: (context, constraints) {
        final m = PlayerOverlayMetrics.loadingHud(
          slotWidth: constraints.maxWidth,
          slotHeight: constraints.maxHeight,
          screenWidth: screenWidth,
        );
        final displayPercent = (widget.progress * 100).toInt();

        return Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final val = _controller.value;

              return SizedBox(
                width: m.outerDiameter,
                height: m.outerDiameter,
                child: Container(
                  width: m.outerDiameter,
                  height: m.outerDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0C0C0E).withAlpha(140),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFE50914)
                            .withOpacity(0.08 + 0.06 * val),
                        blurRadius: m.glowBlur,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: m.ringDiameter,
                        height: m.ringDiameter,
                        child: CircularProgressIndicator(
                          value: widget.progress,
                          strokeWidth: m.strokeWidth,
                          backgroundColor: Colors.white.withAlpha(8),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFE50914),
                          ),
                        ),
                      ),
                      Text(
                        '$displayPercent%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: m.fontSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          shadows: const [
                            Shadow(
                              color: Colors.black45,
                              offset: Offset(0, 1),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
