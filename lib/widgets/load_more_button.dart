import 'dart:ui';
import 'package:flutter/material.dart';
import '../api/mubu_constants.dart';

/// A shared glassmorphic "Load More" button used across all pages.
/// Supports both desktop hover states and mobile tap.
class LoadMoreButton extends StatefulWidget {
  final VoidCallback onTap;

  const LoadMoreButton({
    super.key,
    required this.onTap,
  });

  @override
  State<LoadMoreButton> createState() => _LoadMoreButtonState();
}

class _LoadMoreButtonState extends State<LoadMoreButton> {
  static const _primaryRed = Color(0xFFE50914);
  static const _glassPanel = Color(0xFF16161A);
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 13),
              decoration: BoxDecoration(
                color: _hovered ? _primaryRed : _glassPanel.withOpacity(0.8),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _hovered ? _primaryRed : Colors.white.withOpacity(0.08),
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: _primaryRed.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: _hovered ? Colors.white : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    MubuConstants.loadMore,
                    style: TextStyle(
                      color: _hovered ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
