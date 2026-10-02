# 20261002 — 首页 hand_data 前置

- PRD：`PRD-20261002-02`
- Tickets：`specs/tickets/home-hand-data/01`
- 日期：2026-10-02

## 变更摘要

对齐官方桌面 Category：分类页拉 `/dyTag/hand_data`，各板块第 1 页把手推片前置并按 id 去重；查看全部同样处理。`pc_dyTag` 主路径不变。

## 验证

- [x] `flutter test test/home_hand_data_test.dart`
- [x] `flutter analyze` 相关文件无 error
- [ ] 首页「近期热播」与官方对比冒烟（用户）

## 回滚

去掉 `getHomeHandData` 调用与合并，恢复仅 `getTagVideos`。
