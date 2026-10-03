import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cine/main.dart';
import 'package:cine/api/mubu_api_client.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/models/mubu_hive.dart';
import 'package:cine/utils/device_profile.dart';
import 'package:cine/widgets/movie_sliver_grid.dart';

class _FakeMubuApiClient implements MubuApiClient {
  @override
  String get baseUrl => 'https://fake.test/api';
  @override
  String get imgDomain => 'https://fake.test/img';
  @override
  List<String> get imgDomainCandidates => [imgDomain];
  @override
  Future<void> init() async {}
  @override
  Future<List<CategoryItem>> getHomeCategorys() async => [
        CategoryItem(id: 1, name: '电影'),
        CategoryItem(id: 2, name: '电视剧'),
      ];
  @override
  Future<List<TagItem>> getHomeTags(int categoryId) async => [
        TagItem(id: 101, name: '热门精选', template: 1),
      ];
  @override
  Future<List<VideoItem>> getTagVideos(int tagId, {int tpl = 1, int page = 1, int count = 30}) async => [
        VideoItem(id: 1, title: '测试影片 1', category: '电影', year: '2026', score: '9.0'),
        VideoItem(id: 2, title: '测试影片 2', category: '电影', year: '2026', score: '8.5'),
      ];
  @override
  Future<Map<int, List<VideoItem>>> getHomeHandData(int categoryId) async => {};
  @override
  Future<({List<VideoItem> videos, int total})> search(String keyword, {int page = 1}) async => (videos: <VideoItem>[], total: 0);
  @override
  Future<VideoDetail?> getVideoDetail(int id, {bool isShort = false}) async => null;
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
    final tmpDir = Directory.systemTemp.createTempSync('cine_perf_test');
    Hive.init(tmpDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VideoItemAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(NodeSpeedRecordAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(SourceProbeRecordAdapter());
    await Hive.openBox<VideoItem>('bookmarks', bytes: Uint8List(0));
    await Hive.openBox<VideoItem>('history', bytes: Uint8List(0));
    await Hive.openBox<String>('config', bytes: Uint8List(0));
    await Hive.openBox<NodeSpeedRecord>('node_speeds', bytes: Uint8List(0));
    await Hive.openBox<SourceProbeRecord>('source_probes', bytes: Uint8List(0));
    try {
      MubuApiClient.instance = _FakeMubuApiClient();
    } catch (_) {}
  });

  tearDown(() async {
    await Hive.close();
    DeviceProfile.debugOverride(
      tier: DeviceProfileTier.normal,
      totalMemBytes: null,
      resetInitialized: true,
    );
  });

  testWidgets('Constrained profile keeps low imageCache and responsive layout on low-end pad (800x1280)', (tester) async {
    // 模拟低端平板环境：512MB~1GB RAM, 800x1280 物理分辨率
    DeviceProfile.debugOverride(
      tier: DeviceProfileTier.constrained,
      totalMemBytes: 1024 * 1024 * 1024,
    );
    DeviceProfile.applyImageCacheLimits();

    final cache = PaintingBinding.instance.imageCache;
    expect(cache.maximumSize, 30, reason: '受限档图片数量上限应收缩为 30');
    expect(cache.maximumSizeBytes, 24 * 1024 * 1024, reason: '受限档图片内存上限应收缩为 24MB');

    // 模拟 600 逻辑宽 Pad 视口
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.3333333333333333; // 逻辑宽 600
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(const MubuApp());
    await tester.pump();
    stopwatch.stop();

    expect(find.byType(MubuApp), findsOneWidget);
    // 验证冷启动 pump 耗时低（正常无死锁）
    expect(stopwatch.elapsedMilliseconds, lessThan(3000), reason: '首屏启动渲染应在 3s 内完成');

    // 验证 MovieSliverGrid 列数计算在 600 宽 pad 上表现良好
    final cols = MovieSliverGrid.calculateColumns(600);
    expect(cols, inInclusiveRange(3, 4), reason: '600 逻辑宽 Pad 应展示 3~4 列影片卡');
  });

  testWidgets('TV 4K/1080P large screen surface layout and column calculation', (tester) async {
    // 模拟 1920x1080 TV 屏幕 (逻辑宽 1920)
    final cols = MovieSliverGrid.calculateColumns(1920);
    expect(cols, inInclusiveRange(6, 8), reason: '1080P/4K TV 大屏应展示 6~8 列影片卡以充分利用大屏面积');
  });
}
