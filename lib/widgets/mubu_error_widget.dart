import 'package:flutter/material.dart';
import 'mubu_button.dart';

class MubuErrorWidget extends StatelessWidget {
  final String? title;
  final String error;
  final String buttonText;
  final VoidCallback onRetry;
  final bool isCard;
  final double iconSize;

  const MubuErrorWidget({
    super.key,
    this.title,
    required this.error,
    this.buttonText = '重试',
    required this.onRetry,
    this.isCard = false,
    this.iconSize = 56,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: iconSize,
          color: Colors.white.withOpacity(0.15),
        ),
        const SizedBox(height: 16),
        if (title != null) ...[
          Text(
            title!,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          error,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: title != null ? 12 : 14,
          ),
        ),
        const SizedBox(height: 20),
        MubuButton(
          label: buttonText,
          icon: Icons.refresh_rounded,
          type: MubuButtonType.primary,
          onPressed: onRetry,
        ),
      ],
    );

    if (!isCard) {
      return Center(child: content);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: content,
    );
  }
}
