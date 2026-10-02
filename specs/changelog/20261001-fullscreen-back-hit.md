# 20261001 — 全屏左上角返回命中修复

- PRD：`PRD-20261001-06`
- Tickets：`specs/tickets/fullscreen-back-hit/01`
- 日期：2026-10-01

## 变更摘要

`CineVideoControls` 全屏顶栏抬到中间播控之上；返回键改为 `HitTestBehavior.opaque` 的 48×48 热区，仅调用 `exitFullscreen`（不离页）。

## 验证

- [x] `flutter analyze lib/player/cine_video_controls.dart` 无 error
- [ ] 安卓冒烟：全屏左上角返回只退全屏；右下角与系统返回仍正常

## 回滚

恢复顶栏在 Stack 中位于 Center 之前，并改回 `IconButton`。
