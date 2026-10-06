import 'package:cine/utils/list_viewport_fill.dart';
import 'package:cine/utils/search_viewport_fill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short first page with a larger total still has more', () {
    expect(
      SearchViewportFill.hasMore(
        loadedCount: 10,
        total: 40,
        latestPageCount: 10,
      ),
      isTrue,
    );
  });

  test('empty page stops even when total is larger', () {
    expect(
      SearchViewportFill.hasMore(
        loadedCount: 10,
        total: 40,
        latestPageCount: 0,
      ),
      isFalse,
    );
  });

  test('viewport that cannot scroll asks for another page', () {
    expect(
      SearchViewportFill.needsAnotherPage(
        busy: false,
        hasMore: true,
        autoFills: 0,
        maxScrollExtent: 0,
        viewportDimension: 800,
      ),
      isTrue,
    );
  });

  test('a footer-sized overflow still counts as not filled', () {
    expect(
      SearchViewportFill.needsAnotherPage(
        busy: false,
        hasMore: true,
        autoFills: 0,
        maxScrollExtent: 120,
        viewportDimension: 800,
      ),
      isTrue,
    );
  });

  test('half a viewport of extra rows stops auto paging', () {
    expect(
      SearchViewportFill.needsAnotherPage(
        busy: false,
        hasMore: true,
        autoFills: 0,
        maxScrollExtent: 400,
        viewportDimension: 800,
      ),
      isFalse,
    );
  });

  test('tag page cap of 3 stops sooner than search', () {
    expect(
      ListViewportFill.needsAnotherPage(
        busy: false,
        hasMore: true,
        autoFills: 3,
        maxAutoFills: 3,
        maxScrollExtent: 0,
        viewportDimension: 800,
      ),
      isFalse,
    );
  });

  test('auto fill stops at the cap', () {
    expect(
      SearchViewportFill.needsAnotherPage(
        busy: false,
        hasMore: true,
        autoFills: SearchViewportFill.maxAutoFills,
        maxScrollExtent: 0,
        viewportDimension: 800,
      ),
      isFalse,
    );
  });
}
