# 02 历史卡片显示上次集名
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261002-03
- 依赖：无
- 栈位：ui
- 须装载：cine-flutter-dev

## 交付什么

历史 Tab 卡片副标题优先展示 `lastEpisodeName`；无则回退 year • category。收藏列表保持不显示副标题。

## 验收
- [x] `MovieCard`：`showSubtitle == true` 且 `lastEpisodeName` 非空 → 副标题为集名
- [x] 否则副标题仍为 year • category（可空）
- [x] 首页历史 `MovieSliverGrid`：`showSubtitle: true`
- [x] 收藏仍 `showSubtitle: false`
- [x] `flutter analyze` 无 error

## 笔记
不改 Hive；字段已由 `recordWatch` / `updateProgress` 写入。
