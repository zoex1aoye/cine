import 'package:flutter_test/flutter_test.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/utils/source_picker.dart';
import 'package:cine/utils/source_quality.dart';

VideoSource _src(String name, String ep, int ms, {bool usable = true}) =>
    VideoSource(name: name, sourceName: ep, url: 'https://example.com/$name/$ep.m3u8', speedMs: ms, usable: usable);

void main() {
  group('SourceQuality', () {
    test('classifies audit labels', () {
      expect(SourceQuality.classify('高清线路2'), QualityTier.hd);
      expect(SourceQuality.classify('极速蓝光'), QualityTier.bluRay);
      expect(SourceQuality.classify('VIP线路'), QualityTier.vip);
      expect(SourceQuality.classify('标清'), QualityTier.sd);
      expect(SourceQuality.classify('流畅'), QualityTier.smooth);
      expect(SourceQuality.classify('LZ线路'), QualityTier.cdn);
    });

    test('rank prefers hd over bluRay', () {
      expect(
        SourceQuality.rank(QualityTier.hd),
        greaterThan(SourceQuality.rank(QualityTier.bluRay)),
      );
    });
  });

  group('SourcePicker.pickMain', () {
    const ep = '第01集';

    test('all tiers under 500ms picks 高清', () {
      final sources = [
        _src('流畅', ep, 80),
        _src('极速蓝光', ep, 95),
        _src('高清线路1', ep, 120),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '高清线路1');
    });

    test('only bluRay and smooth qualify picks bluRay', () {
      final sources = [
        _src('流畅', ep, 100),
        _src('极速蓝光', ep, 150),
        _src('高清线路1', ep, 600),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '极速蓝光');
    });

    test('hd 600ms and bluRay 400ms uses acceptable pool picks bluRay', () {
      final sources = [
        _src('高清线路2', ep, 600),
        _src('极速蓝光', ep, 400),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '极速蓝光');
    });

    test('excludes main url when requested via pickPreview', () {
      final main = _src('高清线路1', ep, 100);
      final sources = [
        main,
        _src('流畅', ep, 90),
        _src('标清', ep, 110),
      ];
      final preview = SourcePicker.pickPreview(
        sources,
        episodeName: ep,
        excludeUrl: main.url,
      );
      expect(preview?.name, '流畅');
    });

    test('indexOfFastest returns lowest ms', () {
      final sources = [
        _src('高清线路1', ep, 200),
        _src('极速蓝光', ep, 80),
      ];
      final idx = SourcePicker.indexOfFastest(sources, episodeName: ep);
      expect(idx, 1);
    });
  });
}
