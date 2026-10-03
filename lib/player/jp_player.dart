import 'package:flutter/widgets.dart';

abstract class JpPlayer {
  // Initialization
  Future<void> initialize();

  // Control APIs
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSource(String url, {bool autoPlay = true});
  Future<void> dispose();

  /// 切换硬解/软解模式（如果底层平台支持）
  Future<void> toggleDecodeMode() async {}

  // ValueNotifiers for state observation
  ValueNotifier<bool> get isInitializedNotifier;
  ValueNotifier<bool> get isPlayingNotifier;
  ValueNotifier<Duration> get positionNotifier;
  ValueNotifier<Duration> get durationNotifier;
  ValueNotifier<bool> get isBufferingNotifier;
  ValueNotifier<int?> get videoWidthNotifier;
  ValueNotifier<int?> get videoHeightNotifier;
  ValueNotifier<bool> get isHardwareDecodeNotifier => ValueNotifier(true);

  // Build the video rendering widget
  Widget buildVideoWidget(BuildContext context, {String? title});
}
