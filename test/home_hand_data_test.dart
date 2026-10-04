import 'package:flutter_test/flutter_test.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/utils/home_hand_data.dart';

void main() {
  VideoItem v(int id) => VideoItem(id: id, title: 't$id');

  test('page 1 prepends hand data and dedupes', () {
    final out = mergeHomeHandFirstPage(
      tagId: 10,
      page: 1,
      count: 3,
      tplVideos: [v(2), v(3), v(4)],
      handData: {
        10: [v(1), v(2)],
      },
    );
    expect(out.map((e) => e.id).toList(), [1, 2, 3]);
  });

  test('later pages ignore hand data', () {
    final tpl = [v(9)];
    final out = mergeHomeHandFirstPage(
      tagId: 10,
      page: 2,
      count: 3,
      tplVideos: tpl,
      handData: {
        10: [v(1)],
      },
    );
    expect(out, same(tpl));
  });

  test('feed publishes a section before hand data, then remakes it', () {
    final feed = HomeTagFeed(count: 3);
    feed.setRaw(10, [v(2), v(3), v(4)]);
    expect(feed.videosFor(10)!.map((e) => e.id).toList(), [2, 3, 4]);
    expect(feed.videosFor(11), isNull);

    feed.setHand({
      10: [v(1), v(2)],
    });
    expect(feed.videosFor(10)!.map((e) => e.id).toList(), [1, 2, 3]);

    feed.setRaw(11, [v(8)]);
    expect(feed.videosFor(11)!.map((e) => e.id).toList(), [8]);
  });

  test('missing tag keeps tpl list', () {
    final tpl = [v(5)];
    final out = mergeHomeHandFirstPage(
      tagId: 10,
      page: 1,
      count: 3,
      tplVideos: tpl,
      handData: {},
    );
    expect(out, same(tpl));
  });
}
