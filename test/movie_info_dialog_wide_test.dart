import 'dart:io';
import 'dart:typed_data';

import 'package:cine/api/mubu_api_client.dart';
import 'package:cine/models/mubu_hive.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/widgets/mubu_button.dart';
import 'package:cine/widgets/movie_info_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeApi implements MubuApiClient {
  @override
  String get baseUrl => 'https://fake.test/api';
  @override
  String get imgDomain => 'https://fake.test/img';
  @override
  List<String> get imgDomainCandidates => [imgDomain];
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
  }) async => (videos: <VideoItem>[], total: 0);
  @override
  Future<VideoDetail?> getVideoDetail(int id, {bool isShort = false}) async {
    return VideoDetail(
      id: id,
      title: 'K-POP：猎魔女团',
      year: '2026',
      score: '9.0',
      description: '她们不只是演唱会上一票难求的人气女团，更是斩妖除魔的超强高手！',
    );
  }

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
  setUp(() async {
    final tmpDir = Directory.systemTemp.createTempSync('cine_dialog_wide');
    Hive.init(tmpDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VideoItemAdapter());
    if (!Hive.isBoxOpen('bookmarks')) {
      await Hive.openBox<VideoItem>('bookmarks', bytes: Uint8List(0));
    }
    try {
      MubuApiClient.instance = _FakeApi();
    } catch (_) {}
  });

  testWidgets('1080p 详情弹层跟着放大，不再卡在 640', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => MovieInfoDialog.show(
                  context: context,
                  video: VideoItem(
                    id: 1,
                    title: 'K-POP：猎魔女团',
                    category: '动漫',
                    year: '2026',
                    score: '9.0',
                  ),
                  imgDomain: 'https://fake.test/img',
                  isShort: false,
                  onPlay: () {},
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final sheet = tester.getSize(find.byType(BottomSheet));
    expect(sheet.width, greaterThan(640));

    final play = tester.getSize(find.widgetWithText(MubuButton, '开始播放'));
    expect(play.width, greaterThan(play.height * 2));

    final overflow = errors
        .map((e) => e.exceptionAsString())
        .where((m) => m.contains('overflowed'))
        .toList();
    expect(overflow, isEmpty, reason: overflow.join('\n'));
  });
}
