import 'package:cine/api/mubu_api_client.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/pages/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PagingSearchApi implements MubuApiClient {
  final List<int> pages = [];

  @override
  String get baseUrl => 'https://fake.test/api';
  @override
  String get imgDomain => '';
  @override
  List<String> get imgDomainCandidates => const [];
  @override
  Future<void> init() async {}
  @override
  Future<List<CategoryItem>> getHomeCategorys() async => [];
  @override
  Future<List<TagItem>> getHomeTags(int categoryId) async => [];
  @override
  Future<List<VideoItem>> getTagVideos(
    int tagId, {
    int tpl = 1,
    int page = 1,
    int count = 30,
  }) async => [];
  @override
  Future<Map<int, List<VideoItem>>> getHomeHandData(int categoryId) async => {};
  @override
  Future<({List<VideoItem> videos, int total})> search(
    String keyword, {
    int page = 1,
  }) async {
    pages.add(page);
    final start = (page - 1) * 10;
    return (
      videos: [
        for (var i = 0; i < 10; i++)
          VideoItem(id: start + i + 1, title: '结果${start + i}'),
      ],
      total: 100,
    );
  }

  @override
  Future<VideoDetail?> getVideoDetail(int id, {bool isShort = false}) async =>
      null;
  @override
  Future<List<FilterGroup>> getFilterOptions(int fcatePid) async => [];
  @override
  Future<List<VideoItem>> getFilteredVideos({
    required int fcatePid,
    String type = '',
    String area = '',
    String year = '',
    String sort = '',
    int page = 1,
  }) async => [];
}

void main() {
  testWidgets('short first page keeps requesting until the window can scroll', (
    tester,
  ) async {
    final api = _PagingSearchApi();
    MubuApiClient.instance = api;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(TextField), '结果');
    await tester.tap(find.text('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(api.pages, contains(2));
    expect(find.textContaining('为您找到'), findsOneWidget);
  });
}
