import 'package:cine/utils/cine_surface.dart';
import 'package:cine/widgets/movie_sliver_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugOverrideSurface(null));

  test('非电视宽屏放宽列数，电视同宽仍不超过 8 列', () {
    debugOverrideSurface(CineSurface.mobile);
    expect(MovieSliverGrid.calculateColumns(2512), 10);

    debugOverrideSurface(CineSurface.tv);
    expect(MovieSliverGrid.calculateColumns(2512), 8);
  });

  test('非电视首页一行按列数请求，窄屏至少 6，列数过多封顶 30', () {
    debugOverrideSurface(CineSurface.mobile);
    expect(MovieSliverGrid.homeTagRowFetchCount(342), 6);
    expect(MovieSliverGrid.homeTagRowFetchCount(2512), 10);
    expect(MovieSliverGrid.homeTagFetchCountForColumns(40), 30);
  });

  test('变宽才补拉，进行中或变窄不请求', () {
    expect(
      MovieSliverGrid.homeTagRowNeedsRefetch(
        lastRequestedCount: 6,
        needed: 10,
        fetching: false,
      ),
      isTrue,
    );
    expect(
      MovieSliverGrid.homeTagRowNeedsRefetch(
        lastRequestedCount: 10,
        needed: 6,
        fetching: false,
      ),
      isFalse,
    );
    expect(
      MovieSliverGrid.homeTagRowNeedsRefetch(
        lastRequestedCount: 6,
        needed: 10,
        fetching: true,
      ),
      isFalse,
    );
  });

  test('电视首页一行固定请求 12', () {
    debugOverrideSurface(CineSurface.tv);
    expect(MovieSliverGrid.homeTagRowFetchCount(342), 12);
    expect(MovieSliverGrid.homeTagRowFetchCount(3792), 12);
  });
}
