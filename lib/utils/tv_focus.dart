import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cine_surface.dart';

/// Wraps [child] with D-pad focus highlight + ActivateIntent when [isTvSurface].
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onActivate;
  final bool autofocus;
  final double borderRadius;

  const TvFocusable({
    super.key,
    required this.child,
    required this.onActivate,
    this.autofocus = false,
    this.borderRadius = 12,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.autofocus) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setFocused(bool focused) {
    if (_focused == focused || !mounted) return;
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvSurface) return widget.child;

    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      onFocusChange: _setFocused,
      onShowFocusHighlight: _setFocused,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _focused ? const Color(0xFFE50914) : Colors.transparent,
            width: 2,
          ),
          boxShadow:
              _focused
                  ? [
                    BoxShadow(
                      color: const Color(0xFFE50914).withOpacity(0.25),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                  : null,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Root shortcuts for TV: map Select to activate; Escape/GoBack pops when possible.
class TvShortcutsShell extends StatelessWidget {
  final Widget child;

  const TvShortcutsShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isTvSurface) return child;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              final nav = Navigator.of(context);
              if (nav.canPop()) nav.pop();
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: child,
        ),
      ),
    );
  }
}
