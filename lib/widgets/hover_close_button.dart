import 'package:flutter/material.dart';

class HoverCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  final double size;
  const HoverCloseButton({super.key, required this.onTap, this.size = 18});

  @override
  State<HoverCloseButton> createState() => _HoverCloseButtonState();
}

class _HoverCloseButtonState extends State<HoverCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withOpacity(0.14)
                  : Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: widget.size,
              color: _hovered ? Colors.white : Colors.white.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }
}
