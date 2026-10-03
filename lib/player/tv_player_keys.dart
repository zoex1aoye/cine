import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// TV 播放页按键所需的动作与状态，便于脱离真实播放器做测试。
class TvPlayerKeyActions {
  const TvPlayerKeyActions({
    required this.controlsVisible,
    required this.showControls,
    required this.seekBy,
    required this.nudgeVolume,
    required this.playOrPause,
    required this.exitFullscreen,
    required this.focusChrome,
  });

  final bool Function() controlsVisible;
  final VoidCallback showControls;
  final void Function(Duration delta) seekBy;
  final void Function(double delta) nudgeVolume;
  final VoidCallback playOrPause;

  /// 退出内部全屏；返回 true 表示确实处于全屏并已退出。
  final bool Function() exitFullscreen;

  /// 把焦点送进控件栏；返回 true 表示成功。
  final bool Function() focusChrome;
}

/// TV 播放页按键策略（挂在控件根 Focus 的 onKeyEvent 上）。
///
/// - 焦点在根节点（`node.hasPrimaryFocus`）：←/→ 快进退 10s，↑/↓ 音量，
///   OK 播放暂停；控件栏可见时 ↑ 改为进入控件栏。
/// - 焦点在控件栏内：方向键/确认键一律放行，交给焦点遍历与按钮自身处理，
///   否则祖先吃掉按键会让底栏/顶栏按钮永远够不到。
/// - 返回键：在控件栏内先回根；在根且处于内部全屏则退出全屏；否则放行。
KeyEventResult handleTvPlayerKey(
  FocusNode node,
  KeyEvent event,
  TvPlayerKeyActions actions,
) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;

  final key = event.logicalKey;
  final inChrome = !node.hasPrimaryFocus;
  final isBack =
      key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;

  if (isBack) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (inChrome) {
      node.requestFocus();
      return KeyEventResult.handled;
    }
    return actions.exitFullscreen()
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  if (inChrome) {
    actions.showControls();
    return KeyEventResult.ignored;
  }

  const seekStep = Duration(seconds: 10);
  if (key == LogicalKeyboardKey.arrowLeft) {
    actions.showControls();
    actions.seekBy(-seekStep);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    actions.showControls();
    actions.seekBy(seekStep);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    if (actions.controlsVisible() && actions.focusChrome()) {
      actions.showControls();
      return KeyEventResult.handled;
    }
    actions.showControls();
    actions.nudgeVolume(5);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    actions.showControls();
    actions.nudgeVolume(-5);
    return KeyEventResult.handled;
  }

  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  if (key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.space) {
    actions.showControls();
    actions.playOrPause();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
