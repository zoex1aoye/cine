import 'package:flutter_test/flutter_test.dart';
import 'package:cine/player/hwdec_policy.dart';

void main() {
  setUp(() {
    HwdecPolicy.debugReset(h264: null, hevc: null, probed: false, softUsed: false);
  });

  tearDown(() {
    HwdecPolicy.debugReset(h264: null, hevc: null, probed: false, softUsed: false);
  });

  group('HwdecPolicy', () {
    test('initial optimistic probe defaults to hardware video supported', () {
      expect(HwdecPolicy.hasAnyHardwareVideo, isTrue);
      expect(HwdecPolicy.initialHwdecProperty(), 'amediacodec,mediacodec');
    });

    test('no hardware decoder sets hwdec=no', () {
      HwdecPolicy.debugReset(h264: false, hevc: false, probed: true);
      expect(HwdecPolicy.hasAnyHardwareVideo, isFalse);
      expect(HwdecPolicy.initialHwdecProperty(), 'no');
    });

    test('has either h264 or hevc hardware sets amediacodec,mediacodec', () {
      HwdecPolicy.debugReset(h264: true, hevc: false, probed: true);
      expect(HwdecPolicy.hasAnyHardwareVideo, isTrue);
      expect(HwdecPolicy.initialHwdecProperty(), 'amediacodec,mediacodec');

      HwdecPolicy.debugReset(h264: false, hevc: true, probed: true);
      expect(HwdecPolicy.hasAnyHardwareVideo, isTrue);
      expect(HwdecPolicy.initialHwdecProperty(), 'amediacodec,mediacodec');
    });

    test('tryConsumeSoftFallback is one-shot until resetSoftFallback', () {
      expect(HwdecPolicy.softFallbackUsed, isFalse);
      final first = HwdecPolicy.tryConsumeSoftFallback();
      expect(first, isTrue);
      expect(HwdecPolicy.softFallbackUsed, isTrue);

      final second = HwdecPolicy.tryConsumeSoftFallback();
      expect(second, isFalse);

      HwdecPolicy.resetSoftFallback();
      expect(HwdecPolicy.softFallbackUsed, isFalse);
      expect(HwdecPolicy.tryConsumeSoftFallback(), isTrue);
    });
  });
}
