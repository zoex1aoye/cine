import 'package:cine/player/hwdec_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    HwdecPolicy.debugReset(h264: null, hevc: null, probed: false);
  });

  tearDown(() {
    HwdecPolicy.debugReset(h264: null, hevc: null, probed: false);
  });

  group('HwdecPolicy 探测', () {
    test('未探测时乐观认为有硬解', () {
      expect(HwdecPolicy.hasAnyHardwareVideo, isTrue);
      expect(HwdecPolicy.initialHwdecProperty(), 'amediacodec,mediacodec');
    });

    test('探测完成但结果缺失时仍乐观（不会误判成无硬解）', () {
      HwdecPolicy.debugReset(h264: null, hevc: null, probed: true);
      expect(HwdecPolicy.hasAnyHardwareVideo, isTrue);
    });

    test('无硬解 → hwdec=no', () {
      HwdecPolicy.debugReset(h264: false, hevc: false, probed: true);
      expect(HwdecPolicy.hasAnyHardwareVideo, isFalse);
      expect(HwdecPolicy.initialHwdecProperty(), 'no');
    });

    test('h264 或 hevc 任一有硬解 → amediacodec,mediacodec', () {
      HwdecPolicy.debugReset(h264: true, hevc: false, probed: true);
      expect(HwdecPolicy.initialHwdecProperty(), 'amediacodec,mediacodec');
      HwdecPolicy.debugReset(h264: false, hevc: true, probed: true);
      expect(HwdecPolicy.initialHwdecProperty(), 'amediacodec,mediacodec');
    });

    test('并发 ensureProbed 共享同一次探测，不会读到半成品', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final a = HwdecPolicy.ensureProbed();
      final b = HwdecPolicy.ensureProbed();
      expect(identical(a, b), isTrue);
      await Future.wait([a, b]);
      expect(
        HwdecPolicy.hasAnyHardwareVideo,
        isTrue,
        reason: '无 channel 时保持乐观默认',
      );
    });

    test('未打开 Hive config box 时偏好读写不抛错', () async {
      expect(HwdecPolicy.userPrefersSoft, isFalse);
      await HwdecPolicy.setUserPrefersSoft(true);
      expect(HwdecPolicy.userPrefersSoft, isFalse);
    });
  });

  group('looksLikeHwdecFailure', () {
    test('命中驱动/表面类失败特征', () {
      for (final line in [
        'could not open hwdec',
        'failed to initialize video decoder',
        'mediacodec dequeue output buffer failed',
        'omx error 0x80001001',
        'c2 error: bad state',
        'amediaerror_unknown',
        'surface abandoned',
        'surface lost while rendering',
        'mediacodec init failed',
      ]) {
        expect(looksLikeHwdecFailure(line), isTrue, reason: line);
      }
    });

    test('不误伤 HLS 常见的单包解码告警', () {
      for (final line in [
        'error while decoding mb 12 34',
        'mediacodec: selected decoder c2.mtk.avc.decoder',
        'mediacodec error concealment enabled',
        'using hardware decoding (mediacodec)',
      ]) {
        expect(looksLikeHwdecFailure(line), isFalse, reason: line);
      }
    });
  });
}
