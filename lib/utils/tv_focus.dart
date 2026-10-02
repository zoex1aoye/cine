import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cine_surface.dart';

/// Wraps [child] with D-pad focus highlight + ActivateIntent when [isTvSurface].
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onActivate;
  final bool autofocus;

  const TvFocusable({
    super.key,
    required this.child,
    required this.onActivate,
    this.autofocus = false,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!isTvSurface) return widget.child;

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: _focused
            ? (Matrix4.identity()..scale(1.08))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused ? const Color(0xFFE50914) : Colors.transparent,
            width: 2,
          ),
          boxShadow: _focused
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
