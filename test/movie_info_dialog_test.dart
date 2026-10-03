import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cine/widgets/movie_info_dialog.dart';
import 'package:cine/models/mubu_models.dart';
import 'package:cine/models/mubu_hive.dart';

void main() {
  setUp(() async {
    final tmpDir = Directory.systemTemp.createTempSync('cine_dialog_test');
    Hive.init(tmpDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VideoItemAdapter());
    }
    await Hive.openBox<VideoItem>('bookmarks', bytes: Uint8List(0));
  });

  tearDown(() async {
    await Hive.close();
  });

  testWidgets('MovieInfoDialog vertically caps poster height to at most 220 in narrow/pad viewport', (tester) async {
    // 模拟低端 Pad: 物理 800x1280，逻辑宽 600 (低于 650 触发竖排布局)
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final video = VideoItem(
      id: 12345,
      title: '低端 Pad 详情弹窗测试影片',
      coverPath: '/test_cover.jpg',
      category: '电影',
      year: '2026',
      score: '9.2',
    );

    final detail = VideoDetail(
      id: 12345,
      title: '低端 Pad 详情弹窗测试影片',
      year: '2026',
      score: '9.2',
      description: '这是一段测试剧情简介。第一行内容用于展示剧情背景。第二行内容用于描述人物关系。第三行内容用于说明事件发展与最终冲突高潮。',
      sources: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MovieInfoDialog(
            video: video,
            imgDomain: 'https://test.img',
            isShort: false,
            preloadedDetail: detail,
            onPlay: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // 找到展示海报的 SizedBox
    final sizedBoxFinders = find.byType(SizedBox);
    bool foundCappedPoster = false;
    for (final element in sizedBoxFinders.evaluate()) {
      final widget = element.widget as SizedBox;
      if (widget.height != null && (widget.height! - 220.0).abs() < 1.0) {
        foundCappedPoster = true;
        break;
      }
    }
    expect(foundCappedPoster, isTrue, reason: '海报高度应被 math.min 封顶在 220 逻辑像素以内');

    // 验证剧情简介 Text 是否正常渲染
    expect(find.textContaining('第一行内容'), findsOneWidget);
    expect(find.textContaining('第三行内容'), findsOneWidget);
  });
}
