// lib/widgets/concentric_hud.dart
import 'package:flutter/material.dart';
import '../models/mubu_models.dart';

/// 轻量化加载指示器 (ConcentricHud)
///
/// 展示播放源测速的进度百分比 + 简洁的进度环。
/// 移动端自适应：窄屏下缩小尺寸，移除冗余视觉元素。
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    // 移动端 ~120px, 桌面 ~180px
    final baseSize = isMobile ? 120.0 : 180.0;
    final ringSize = isMobile ? 80.0 : 130.0;
    final strokeW = isMobile ? 3.0 : 4.0;
    final fontSize = isMobile ? 22.0 : 32.0;

    final displayPercent = (widget.progress * 100).toInt();

    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final val = _controller.value;

          return SizedBox(
            width: baseSize,
            height: baseSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 主容器：暗色圆底 + 微弱呼吸光晕
                Container(
                  width: baseSize,
                  height: baseSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0C0C0E).withAlpha(140),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE50914).withOpacity(0.08 + 0.06 * val),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 进度环
                      SizedBox(
                        width: ringSize,
                        height: ringSize,
                        child: CircularProgressIndicator(
                          value: widget.progress,
                          strokeWidth: strokeW,
                          backgroundColor: Colors.white.withAlpha(8),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                        ),
                      ),
                      // 百分比文字
                      Text(
                        '$displayPercent%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
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
              ],
            ),
          );
        },
      ),
    );
  }
}
