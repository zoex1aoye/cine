import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/mubu_ui_adapt.dart';

enum MubuButtonType { primary, secondary, text, icon }

class MubuButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final MubuButtonType type;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool fullWidth;
  final double? customHeight;
  final double? customWidth;

  const MubuButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.type = MubuButtonType.primary,
    this.autofocus = false,
    this.focusNode,
    this.fullWidth = false,
    this.customHeight,
    this.customWidth,
  });

  @override
  State<MubuButton> createState() => _MubuButtonState();
}

class _MubuButtonState extends State<MubuButton> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;
  late FocusNode _focusNode;

  static const Color kPrimaryRed = Color(0xFFE50914);
  static const Color kPrimaryHover = Color(0xFFF40F1D);
  static const Color kGlowShadow = Color(0x59E50914); // 0.35 opacity

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(MubuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_onFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  void _handleTapDown(_) => setState(() => _isPressed = true);
  void _handleTapUp(_) {
    setState(() => _isPressed = false);
    widget.onPressed?.call();
  }
  void _handleTapCancel() => setState(() => _isPressed = false);

  @override
  Widget build(BuildContext context) {
    final bool disabled = widget.onPressed == null;
    
    // Base dimensions mapped to UIAdapt for automatic cross-platform scaling
    double baseHeight = widget.customHeight ?? UIAdapt.px(context, 44);
    double hPad = UIAdapt.px(context, 20);
    double fontSize = UIAdapt.fontSize(context, 14);
    double iconSize = UIAdapt.px(context, 18);

    // Color resolution based on type
    Color bgColor;
    Color fgColor;
    BorderSide border = BorderSide.none;
    List<BoxShadow>? boxShadow;

    switch (widget.type) {
      case MubuButtonType.primary:
        bgColor = _isHovered || _isFocused ? kPrimaryHover : kPrimaryRed;
        fgColor = Colors.white;
        if ((_isFocused || _isHovered) && !disabled) {
          boxShadow = [
            BoxShadow(
              color: kGlowShadow,
              blurRadius: UIAdapt.px(context, 20),
              spreadRadius: 1,
              offset: Offset(0, UIAdapt.px(context, 4)),
            ),
          ];
        }
        break;
      case MubuButtonType.secondary:
        bgColor = Colors.white.withOpacity(_isHovered || _isFocused ? 0.12 : 0.05);
        fgColor = Colors.white.withOpacity(0.9);
        border = BorderSide(color: Colors.white.withOpacity(_isHovered || _isFocused ? 0.2 : 0.08));
        break;
      case MubuButtonType.text:
        bgColor = _isHovered || _isFocused ? Colors.white.withOpacity(0.08) : Colors.transparent;
        fgColor = _isHovered || _isFocused ? Colors.white : Colors.white.withOpacity(0.6);
        hPad = UIAdapt.px(context, 12);
        break;
      case MubuButtonType.icon:
        bgColor = Colors.white.withOpacity(_isHovered || _isFocused ? 0.12 : 0.06);
        fgColor = Colors.white.withOpacity(0.8);
        border = BorderSide(color: Colors.white.withOpacity(_isHovered || _isFocused ? 0.15 : 0.08));
        hPad = 0; // Handled by aspect ratio or explicit width
        break;
    }

    if (disabled) {
      bgColor = bgColor.withOpacity(0.3);
      fgColor = fgColor.withOpacity(0.3);
      border = BorderSide.none;
      boxShadow = null;
    }

    // Interactive scale: 1.05 when focused (TV style), 0.95 when pressed
    double scale = 1.0;
    if (_isPressed && !disabled) {
      scale = 0.95;
    } else if (_isFocused && !disabled) {
      scale = 1.05;
    }

    // Adjust padding for icon-only buttons (non-icon type but no label)
    double? finalWidth = widget.customWidth;
    if ((widget.label == null || widget.label!.isEmpty) && widget.icon != null) {
      hPad = 0;
      finalWidth ??= baseHeight; // Force it to be a circle if no custom width
    }

    Widget content;
    if (widget.type == MubuButtonType.icon || (widget.label == null || widget.label!.isEmpty)) {
      content = Center(
        child: Icon(widget.icon ?? Icons.circle, size: iconSize, color: fgColor),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: iconSize, color: fgColor),
            if (widget.label != null && widget.label!.isNotEmpty) SizedBox(width: UIAdapt.px(context, 8)),
          ],
          if (widget.label != null && widget.label!.isNotEmpty)
            Flexible(
              child: Text(
                widget.label!,
                style: TextStyle(
                  color: fgColor,
                  fontSize: fontSize,
                  fontWeight: widget.type == MubuButtonType.primary ? FontWeight.bold : FontWeight.w600,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      );
    }

    Widget container = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: baseHeight,
      width: widget.fullWidth ? double.infinity : finalWidth,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100), // Pill-shaped
        border: border != BorderSide.none ? Border.fromBorderSide(border) : null,
        boxShadow: boxShadow,
      ),
      child: content,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: disabled ? null : _handleTapDown,
        onTapUp: disabled ? null : _handleTapUp,
        onTapCancel: disabled ? null : _handleTapCancel,
        behavior: HitTestBehavior.opaque,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKey: (node, event) {
            if (!disabled &&
                event is RawKeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                 event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onPressed?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            child: container,
          ),
        ),
      ),
    );
  }
}
