# 01 MovieCard 底部 Scrim 叠字
- 状态： [x] 完成
- PRD：PRD-20261014-01
- 依赖：无
- 栈位：ui
- 须装载：cine-flutter-dev

## 交付什么
`MovieCard` 去掉实心 footer，封面铺满卡片，底部约 30% scrim 上叠标题/副标题；评分、进度、悬停、删除、TV 焦点行为保持。

## 验收
- [x] 无独立 `SizedBox(height: 40/52)` 底栏
- [x] 底部 scrim ≈ 封面高 30%，渐变叠字可读
- [x] 副标题逻辑与改前一致（含历史集名）
- [x] `flutter analyze` 无 error
- [x] `flutter test test/tv_surface_card_test.dart` 通过

## 笔记
- 进度条仍贴卡片底边；悬停时隐藏逻辑保留
- 勿引入底部 `BackdropFilter`
