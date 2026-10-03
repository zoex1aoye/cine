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

  /// 当前平台是否支持用户手动切换硬解/软解（仅 Android 原生实现为 true）。
  bool get supportsDecodeToggle;

  /// 切换硬解/软解；不支持的平台为 no-op。
  Future<void> toggleDecodeMode();

  // ValueNotifiers for state observation
  ValueNotifier<bool> get isInitializedNotifier;
  ValueNotifier<bool> get isPlayingNotifier;
  ValueNotifier<Duration> get positionNotifier;
  ValueNotifier<Duration> get durationNotifier;
  ValueNotifier<bool> get isBufferingNotifier;
  ValueNotifier<int?> get videoWidthNotifier;
  ValueNotifier<int?> get videoHeightNotifier;
  ValueNotifier<bool> get isHardwareDecodeNotifier;

  // Build the video rendering widget
  Widget buildVideoWidget(BuildContext context, {String? title});
}
