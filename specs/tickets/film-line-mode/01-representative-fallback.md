# 01 线路代表源回退 + 测速门槛
- 状态： [x] 完成
- PRD：PRD-20261001-04
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

代表源查找改为「当前集优先、否则该线首源」；单源也跑测速；探测中止/跳过时写入终态，消除永久「检测中」。

## 验收

- [x] `_representativeIndexForLine` / `_representativeForLine`：无集匹配时回退该 `lineName` 首源
- [x] `_loadAndPrepare`：有源即 `_runSpeedTest`（不再要求 `length > 1`）
- [x] `_runSpeedTest`：未测完的线路 `playlistMs` 终态化为 999999
- [x] 单测覆盖代表源回退（`test/episode_utils_test.dart`）
- [x] `flutter analyze` 无 error

## 笔记

纯函数 `representativeIndexForLine` 落在 `lib/utils/episode_utils.dart`。
