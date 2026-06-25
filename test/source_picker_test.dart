import 'package:flutter_test/flutter_test.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/utils/source_picker.dart';
import 'package:cine/utils/source_quality.dart';
import 'package:cine/utils/stream_probe.dart';

VideoSource _src(
  String name,
  String ep,
  int ms, {
  bool usable = true,
  QualityTier? probedTier,
}) =>
    VideoSource(
      name: name,
      sourceName: ep,
      url: 'https://example.com/$name/$ep.m3u8',
      speedMs: ms,
      usable: usable,
      probedTier: probedTier,
    );

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

    test('tierFromProbe maps resolution', () {
      expect(
        SourceQuality.tierFromProbe(1920, 1080, 5000),
        QualityTier.hd,
      );
      expect(
        SourceQuality.tierFromProbe(1280, 720, 2500),
        QualityTier.sd,
      );
    });
  });

  group('StreamProbe parsing', () {
    test('pickBestVariant selects highest bandwidth', () {
      const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
mid/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
high/index.m3u8
''';
      final result = StreamProbe.pickBestVariant(
        master,
        Uri.parse('https://cdn.example.com/master.m3u8'),
      );
      expect(result, isNotNull);
      expect(result!.key, 5000000);
      expect(result.value.toString(), contains('high/index.m3u8'));
    });

    test('selectionMs prefers full startup path', () {
      const r = StreamProbeResult(
        success: true,
        playlistMs: 40,
        firstFrameMs: 180,
        startupMs: 350,
      );
      expect(r.selectionMs, 350);
    });

    test('firstSegmentUrl resolves relative path', () {
      const media = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
seg001.ts
''';
      final uri = StreamProbe.firstSegmentUrl(
        media,
        Uri.parse('https://cdn.example.com/vod/playlist.m3u8'),
      );
      expect(uri.toString(), 'https://cdn.example.com/vod/seg001.ts');
    });
  });

  group('SourcePicker.pickMain', () {
    const ep = '第01集';

    test('all tiers under 500ms picks 高清 (highest tier champion)', () {
      final sources = [
        _src('流畅', ep, 80),
        _src('极速蓝光', ep, 95),
        _src('高清线路1', ep, 120),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '高清线路1');
    });

    test('same tier picks lowest latency', () {
      final sources = [
        _src('高清线路1', ep, 150),
        _src('高清线路2', ep, 80),
        _src('极速蓝光', ep, 200),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '高清线路2');
    });

    test('CDN probed as hd groups with 高清 and picks faster hd', () {
      final sources = [
        _src('高清线路1', ep, 150),
        _src('LZ线路', ep, 90, probedTier: QualityTier.hd),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, 'LZ线路');
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

    test('indexOfFastest within tier returns lowest ms', () {
      final sources = [
        _src('高清线路1', ep, 200),
        _src('高清线路2', ep, 80),
        _src('极速蓝光', ep, 50),
      ];
      final idx = SourcePicker.indexOfFastest(
        sources,
        episodeName: ep,
        withinTier: QualityTier.hd,
      );
      expect(idx, 1);
    });
  });
}
