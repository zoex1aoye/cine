// media_kit_player_stub.dart – web stub implementation
import 'package:flutter/widgets.dart';
import '../player/jp_player.dart';

class MediaKitPlayerImpl implements JpPlayer {
  final bool isShort;
  MediaKitPlayerImpl({required String initialUrl, this.isShort = false});

  final _isInitialized = ValueNotifier<bool>(true);
  final _isPlaying = ValueNotifier<bool>(false);
  final _position = ValueNotifier<Duration>(Duration.zero);
  final _duration = ValueNotifier<Duration>(Duration.zero);
  final _isBuffering = ValueNotifier<bool>(false);
  final _videoWidth = ValueNotifier<int?>(null);
  final _videoHeight = ValueNotifier<int?>(null);

  @override
  ValueNotifier<bool> get isInitializedNotifier => _isInitialized;

  @override
  ValueNotifier<bool> get isPlayingNotifier => _isPlaying;

  @override
  ValueNotifier<Duration> get positionNotifier => _position;

  @override
  ValueNotifier<Duration> get durationNotifier => _duration;

  @override
  ValueNotifier<bool> get isBufferingNotifier => _isBuffering;

  @override
  ValueNotifier<int?> get videoWidthNotifier => _videoWidth;

  @override
  ValueNotifier<int?> get videoHeightNotifier => _videoHeight;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSource(String url, {bool autoPlay = true}) async {}

  @override
  Future<void> dispose() async {
    _isInitialized.dispose();
    _isPlaying.dispose();
    _position.dispose();
    _duration.dispose();
    _isBuffering.dispose();
    _videoWidth.dispose();
    _videoHeight.dispose();
  }

  @override
  Widget buildVideoWidget(BuildContext context) => const SizedBox.shrink();
}
