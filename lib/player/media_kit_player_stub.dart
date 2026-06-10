// media_kit_player_stub.dart – web stub implementation
import 'package:flutter/widgets.dart';
import '../player/jp_player.dart';

class MediaKitPlayerImpl implements JpPlayer {
  MediaKitPlayerImpl({required String initialUrl});

  @override
  ValueNotifier<bool> get isInitializedNotifier => ValueNotifier<bool>(true);

  @override
  ValueNotifier<bool> get isPlayingNotifier => ValueNotifier<bool>(false);

  @override
  ValueNotifier<Duration> get positionNotifier => ValueNotifier<Duration>(Duration.zero);

  @override
  ValueNotifier<Duration> get durationNotifier => ValueNotifier<Duration>(Duration.zero);

  @override
  ValueNotifier<bool> get isBufferingNotifier => ValueNotifier<bool>(false);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSource(String url) async {}

  @override
  Future<void> dispose() async {}

  @override
  Widget buildVideoWidget(BuildContext context) => const SizedBox.shrink();
}
