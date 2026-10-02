# 20261002 — 缓冲速度避开中心播控

- PRD：`PRD-20261002-03`
- Tickets：`specs/tickets/buffer-speed-offset/01`
- 日期：2026-10-02

## 变更摘要

缓冲转圈+「加载中 {速度}」由居中改为 `Alignment(0, 0.42)` 偏下，避免与中心播放按钮重叠。

## 验证

- [x] `flutter analyze lib/player/cine_video_controls.dart` 无 error
- [ ] 冒烟：缓冲时速度在播控下方（用户）

## 回滚

恢复缓冲 HUD 的 `Center`。
