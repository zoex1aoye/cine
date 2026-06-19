import 'dart:ui';
import 'package:flutter/material.dart';
import 'mubu_button.dart';

class MubuDialog {
  /// 显示标准带标题和底部操作按钮的 Mubu 风格对话框
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    String? cancelText,
    String? confirmText,
    VoidCallback? onCancel,
    VoidCallback? onConfirm,
    bool barrierDismissible = true,
    double maxWidth = 480,
  }) {
    return showCustom<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) {
        return MubuDialogContainer(
          maxWidth: maxWidth,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                DefaultTextStyle(
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 15,
                    height: 1.5,
                  ),
                  child: content,
                ),
                if (cancelText != null || confirmText != null) ...[
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (cancelText != null)
                        MubuButton(
                          label: cancelText,
                          type: MubuButtonType.secondary,
                          onPressed: () {
                            if (onCancel != null) onCancel();
                            Navigator.of(ctx).pop();
                          },
                        ),
                      if (cancelText != null && confirmText != null)
                        const SizedBox(width: 12),
                      if (confirmText != null)
                        MubuButton(
                          label: confirmText,
                          type: MubuButtonType.primary,
                          autofocus: true,
                          onPressed: () {
                            if (onConfirm != null) {
                              onConfirm();
                            } else {
                              Navigator.of(ctx).pop();
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示完全自定义内容的 Mubu 风格对话框（提供 Z 轴模糊遮罩和标准动效）
  static Future<T?> showCustom<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'MubuDialog',
      barrierColor: Colors.transparent, // Handled manually for blur
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return builder(context);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final scale = Tween<double>(begin: 0.95, end: 1.0).animate(curvedAnimation);
        final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Z-axis spatial backdrop blur (sigma 5)
              FadeTransition(
                opacity: opacity,
                child: GestureDetector(
                  onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
                  behavior: HitTestBehavior.opaque,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(color: Colors.black.withOpacity(0.5)),
                  ),
                ),
              ),
              // Dialog Content
              Center(
                child: FadeTransition(
                  opacity: opacity,
                  child: ScaleTransition(
                    scale: scale,
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 电影感毛玻璃对话框容器
class MubuDialogContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  const MubuDialogContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.margin = const EdgeInsets.symmetric(horizontal: 24),
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    Widget container = Container(
      width: maxWidth,
      margin: margin,
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withOpacity(0.85),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: child,
        ),
      ),
    );
    
    // To prevent the gesture detector of the backdrop from dismissing
    // when tapping inside the container
    return GestureDetector(
      onTap: () {}, // absorb taps
      child: container,
    );
  }
}
