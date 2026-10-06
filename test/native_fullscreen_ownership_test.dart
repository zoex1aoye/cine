import 'package:cine/player/native_fullscreen_ownership.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player does not own a fullscreen the user already opened', () {
    expect(
      playerOwnsNativeFullscreen(windowAlreadyFullscreen: true),
      isFalse,
    );
  });

  test('player owns fullscreen it opens from a windowed state', () {
    expect(
      playerOwnsNativeFullscreen(windowAlreadyFullscreen: false),
      isTrue,
    );
  });
}
