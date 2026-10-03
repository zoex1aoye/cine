import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cine/main.dart';
import 'package:cine/api/mubu_api_client.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/models/mubu_hive.dart';

/// 红线 #4：pump MubuApp 前必须赋值 MubuApiClient.instance。
/// 这里用空实现 Fake，仅验证应用能启动渲染，不发网络请求。
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
  Future<List<CategoryItem>> getHomeCategorys() async => [];
  @override
  Future<List<TagItem>> getHomeTags(int categoryId) async => [];
  @override
  Future<List<VideoItem>> getTagVideos(int tagId, {int tpl = 1, int page = 1, int count = 30}) async => [];
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
  testWidgets('App starts', (WidgetTester tester) async {
    final tmpDir = Directory.systemTemp.createTempSync('cine_widget_test');
    Hive.init(tmpDir.path);
    Hive.registerAdapter(VideoItemAdapter());
    Hive.registerAdapter(NodeSpeedRecordAdapter());
    Hive.registerAdapter(SourceProbeRecordAdapter());
    await Hive.openBox<VideoItem>('bookmarks', bytes: Uint8List(0));
    await Hive.openBox<VideoItem>('history', bytes: Uint8List(0));
    await Hive.openBox<String>('config', bytes: Uint8List(0));
    await Hive.openBox<NodeSpeedRecord>('node_speeds', bytes: Uint8List(0));
    await Hive.openBox<SourceProbeRecord>('source_probes', bytes: Uint8List(0));

    MubuApiClient.instance = _FakeMubuApiClient();
    await tester.pumpWidget(const MubuApp());
    expect(find.byType(MubuApp), findsOneWidget);
  });
}
