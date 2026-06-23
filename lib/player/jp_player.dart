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

  // ValueNotifiers for state observation
  ValueNotifier<bool> get isInitializedNotifier;
  ValueNotifier<bool> get isPlayingNotifier;
  ValueNotifier<Duration> get positionNotifier;
  ValueNotifier<Duration> get durationNotifier;
  ValueNotifier<bool> get isBufferingNotifier;
  ValueNotifier<int?> get videoWidthNotifier;
  ValueNotifier<int?> get videoHeightNotifier;

  // Build the video rendering widget
  Widget buildVideoWidget(BuildContext context, {String? title, VoidCallback? onBack, String? previewUrl});
}
