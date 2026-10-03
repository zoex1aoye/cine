import 'dart:async';

/// 硬解静默假死看门狗。
///
/// 只在「硬解生效 + 有视频轨 + 正在播放 + 未在缓冲」期间累计时间，
/// 弱网缓冲、暂停都会清零计时，避免把网络问题误判成解码器假死。
/// 到点后用 [hasRenderedFrame] 实测解码输出；探测不可用（抛错/返回 null）时
/// 一律视为正常，宁可漏判也不误切软解。
class HwdecWatchdog {
  HwdecWatchdog({
    required this.hasRenderedFrame,
    required this.onStall,
    this.timeout = const Duration(seconds: 5),
  });

  /// 返回 true=已有帧输出；false=确认无帧；null=无法判断。
  final Future<bool?> Function() hasRenderedFrame;
  final void Function() onStall;
  final Duration timeout;

  Timer? _timer;
  bool _enabled = false;
  bool _hasVideoTrack = false;
  bool _playing = false;
  bool _buffering = false;
  bool _satisfied = false;
  bool _disposed = false;

  bool get isRunning => _timer != null;

  /// 硬解是否生效（软解、用户强制软解时关闭）。
  void setEnabled(bool value) => _update(() => _enabled = value);
  void setHasVideoTrack(bool value) => _update(() => _hasVideoTrack = value);
  void setPlaying(bool value) => _update(() => _playing = value);
  void setBuffering(bool value) => _update(() => _buffering = value);

  /// 已确认有帧输出（如宽高事件到达），本源不再监控。
  void markFrameRendered() => _update(() => _satisfied = true);

  /// 装载新视频源：清掉「已满足」，重新监控。
  void resetForNewSource() {
    _satisfied = false;
    _hasVideoTrack = false;
    _update(() {});
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }

  bool get _shouldRun =>
      !_disposed &&
      _enabled &&
      !_satisfied &&
      _hasVideoTrack &&
      _playing &&
      !_buffering;

  void _update(void Function() mutate) {
    mutate();
    if (_shouldRun) {
      _timer ??= Timer(timeout, _onTimeout);
    } else {
      _cancel();
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _onTimeout() async {
    _timer = null;
    if (!_shouldRun) return;
    bool? rendered;
    try {
      rendered = await hasRenderedFrame();
    } catch (_) {
      rendered = null;
    }
    if (!_shouldRun) return;
    if (rendered == false) {
      _satisfied = true;
      onStall();
    } else {
      _satisfied = true;
    }
  }
}
