import 'package:cine/models/mubu_models.dart';
import 'package:cine/utils/episode_utils.dart';
import 'package:flutter_test/flutter_test.dart';

VideoSource _src(String line, String ep) => VideoSource(
      name: line,
      sourceName: ep,
      weight: ep,
      url: 'https://example.com/$line/$ep.m3u8',
    );

void main() {
  group('representativeIndexForLine', () {
    test('prefers current episode match', () {
      final sources = [
        _src('VIP线路', '日语中字'),
        _src('VIP线路', '国语中字'),
        _src('LZ线路', '日语中字'),
        _src('极速蓝光', 'BD国粤日三语中字'),
      ];
      expect(
        representativeIndexForLine(sources, 'VIP线路', episodeRef: '国语中字'),
        1,
      );
      expect(
        representativeIndexForLine(sources, 'LZ线路', episodeRef: '日语中字'),
        2,
      );
    });

    test('falls back to first source on line when episode labels diverge', () {
      // Film: each CDN uses a distinct version label (crayon-shinchan pattern).
      final sources = [
        _src('VIP线路', '日语中字'),
        _src('极速蓝光', 'BD国粤日三语中字'),
        _src('蓝光线路', '1080P'),
        _src('JY线路', '正片'),
      ];
      expect(
        representativeIndexForLine(
          sources,
          'JY线路',
          episodeRef: 'BD国粤日三语中字',
        ),
        3,
      );
      expect(
        representativeIndexForLine(
          sources,
          '极速蓝光',
          episodeRef: '日语中字',
        ),
        1,
      );
    });

    test('film-style unique lines are all resolvable under any episode scope', () {
      final sources = [
        _src('VIP线路', '日语中字'),
        _src('极速蓝光', 'BD国粤日三语中字'),
        _src('蓝光线路', '1080P'),
        _src('高清线路2', '高清'),
        _src('JY线路', '正片'),
        _src('LZ线路', '国语中字'),
      ];
      const scope = 'BD国粤日三语中字';
      final lines = {for (final s in sources) s.name};
      for (final line in lines) {
        final idx = representativeIndexForLine(
          sources,
          line,
          episodeRef: scope,
        );
        expect(idx, isNonNegative, reason: 'line $line should resolve');
        expect(sources[idx].name, line);
      }
      expect(lines.length, 6);
    });

    test('returns -1 for unknown line', () {
      expect(
        representativeIndexForLine(
          [_src('VIP线路', '日语中字')],
          '不存在',
          episodeRef: '日语中字',
        ),
        -1,
      );
    });
  });

  group('isFilmStyleSources / pickScopeEpisodeName', () {
    test('crayon-like version labels are film-style', () {
      final sources = [
        _src('VIP线路', '日语中字'),
        _src('极速蓝光', 'BD国粤日三语中字'),
        _src('蓝光线路', '1080P'),
        _src('JY线路', '正片'),
      ];
      expect(isFilmStyleSources(sources), isTrue);
      expect(pickScopeEpisodeName(sources, '日语中字'), isEmpty);
    });

    test('numbered episodes are series-style', () {
      final sources = [
        _src('LZ线路', '第01集'),
        _src('SN线路', '第01集'),
        _src('LZ线路', '第02集'),
        _src('SN线路', '第02集'),
      ];
      expect(isFilmStyleSources(sources), isFalse);
      expect(pickScopeEpisodeName(sources, '第01集'), '第01集');
    });
  });
}
