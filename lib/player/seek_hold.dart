/// 左右键跳进度：短按 10 秒；按住后加大步长，并限制发送频率。
class SeekHold {
  static const freshGap = Duration(milliseconds: 400);
  static const minInterval = Duration(milliseconds: 200);
  static const gear30 = Duration(milliseconds: 700);
  static const gear60 = Duration(milliseconds: 1600);

  int? _sign;
  Duration? _started;
  Duration? _lastEvent;
  Duration? _lastEmit;

  void reset() {
    _sign = null;
    _started = null;
    _lastEvent = null;
    _lastEmit = null;
  }

  /// 返回带符号的秒数。这次按键不该跳时返回 null。
  int? take(int sign, Duration now) {
    final previousEvent = _lastEvent;
    final fresh =
        _sign != sign ||
        _started == null ||
        previousEvent == null ||
        now - previousEvent > freshGap;
    _lastEvent = now;
    if (fresh) {
      _sign = sign;
      _started = now;
      _lastEmit = now;
      return sign * 10;
    }
    final lastEmit = _lastEmit!;
    if (now - lastEmit < minInterval) return null;
    final held = now - _started!;
    final step =
        held >= gear60
            ? 60
            : held >= gear30
            ? 30
            : 10;
    _lastEmit = now;
    return sign * step;
  }
}
