import 'package:flutter_test/flutter_test.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/utils/episode_utils.dart';
import 'package:cine/utils/source_picker.dart';
import 'package:cine/utils/source_quality.dart';
import 'package:cine/utils/stream_probe.dart';

VideoSource _src(
  String name,
  String ep,
  int ms, {
  bool usable = true,
  int probeWidth = 1920,
  int probeHeight = 1080,
  String weight = '',
}) =>
    VideoSource(
      name: name,
      sourceName: ep,
      weight: weight,
      url: 'https://example.com/$name/$ep.m3u8',
      playlistMs: ms,
      usable: usable,
      probeWidth: probeWidth,
      probeHeight: probeHeight,
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

    test('resolutionLabel from probe dimensions', () {
      expect(
        SourceQuality.resolutionLabel(_src('a', 'ep', 1)),
        '1080P',
      );
      expect(
        SourceQuality.resolutionLabel(
          _src('b', 'ep', 1, probeWidth: 1280, probeHeight: 720),
        ),
        '720P',
      );
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
    test('pickLowestVariant selects lowest bandwidth', () {
      const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
high/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
''';
      final result = StreamProbe.pickLowestVariant(
        master,
        Uri.parse('https://cdn.example.com/master.m3u8'),
      );
      expect(result, isNotNull);
      expect(result!.key, 800000);
      expect(result.value.toString(), contains('low/index.m3u8'));
    });

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

  group('episodeRef / matchesEpisode', () {
    test('episodeRef prefers source_name over weight', () {
      final s = _src('SN线路', 'HD国语', 1, weight: 'mirror-w1');
      expect(episodeRef(s), 'HD国语');
      expect(matchesEpisode(_src('JS线路', 'HD国语', 1, weight: 'mirror-w2'), 'HD国语'), isTrue);
    });
  });

  group('SourcePicker.pickMain', () {
    const ep = '第01集';

    test('close latency tie-breaks toward sharper resolution', () {
      final sources = [
        _src('流畅', ep, 80, probeWidth: 640, probeHeight: 360),
        _src('极速蓝光', ep, 95),
        _src('高清线路1', ep, 120),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '极速蓝光');
    });

    test('large latency gap prefers faster line over resolution', () {
      final sources = [
        _src('720线', ep, 80, probeWidth: 1280, probeHeight: 720),
        _src('1080线', ep, 300),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '720线');
    });

    test('resolution tie-breaks when latency is close', () {
      final sources = [
        _src('720线', ep, 100, probeWidth: 1280, probeHeight: 720),
        _src('1080线', ep, 150),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: ep);
      expect(picked?.name, '1080线');
    });

    test('falls back globally when episode group has no usable lines', () {
      final sources = [
        _src('极速蓝光', 'BD英语', 999999, usable: false),
        _src('高清线路3', '其他版本', 956),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: 'BD英语');
      expect(picked?.name, '高清线路3');
    });

    test('scopes CDN mirrors by shared source_name', () {
      const epName = 'HD国语';
      final sources = [
        _src('高速蓝光', epName, 1200, weight: 'w-bluray'),
        _src('SN线路', epName, 309, probeWidth: 1280, probeHeight: 720, weight: 'w-sn'),
        _src('JS线路', epName, 365, weight: 'w-js'),
      ];
      final picked = SourcePicker.pickMain(sources, episodeName: epName);
      expect(picked?.name, 'SN线路');
    });

    test('indexOfFastest within resolution returns lowest ms', () {
      final sources = [
        _src('高清线路1', ep, 200),
        _src('高清线路2', ep, 80),
        _src('极速蓝光', ep, 50),
      ];
      final idx = SourcePicker.indexOfFastest(
        sources,
        episodeName: ep,
        withinResolution: '1080P',
      );
      expect(idx, 2);
    });
  });
}
