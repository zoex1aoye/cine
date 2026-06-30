import 'package:flutter_test/flutter_test.dart';
import 'package:cine/utils/detail_source_parse.dart';

void main() {
  test('parseDetailSources skips vip list and dedupes urls', () {
    const url = 'https://cdn.example.com/ep1.m3u8';
    final fields = parseDetailSources({
      'vip_source_list_source': [
        {
          'name': '极速蓝光',
          'source_list': [
            {'source_name': '第01集', 'url': url, 'weight': 1},
          ],
        },
      ],
      'source_list_source': [
        {
          'name': '极速蓝光',
          'source_list': [
            {'source_name': '第01集', 'url': url, 'weight': 1},
          ],
        },
        {
          'name': 'LZ线路',
          'source_list': [
            {
              'source_name': '第01集',
              'url': 'https://cdn.example.com/ep1-mirror.m3u8',
              'weight': 1,
              'time_data': {'titles_duration': '90'},
            },
          ],
        },
      ],
    });

    expect(fields.length, 2);
    expect(fields[0].name, '极速蓝光');
    expect(fields[1].name, 'LZ线路');
    expect(fields[1].titlesDurationSec, 90);
  });

  test('parseDetailSources marks non-http as unusable', () {
    final fields = parseDetailSources({
      'source_list_source': [
        {
          'name': 'FTP线路',
          'source_list': [
            {'source_name': '第01集', 'url': 'ftp://host/file.mp4', 'weight': 1},
          ],
        },
      ],
    });
    expect(fields.single.usable, isFalse);
  });
}
