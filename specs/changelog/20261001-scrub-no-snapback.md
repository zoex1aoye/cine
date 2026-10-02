# 20261001 — 进度条松手不回弹

- PRD：`PRD-20261001-07`
- Tickets：`specs/tickets/scrub-no-snapback/01`
- 日期：2026-10-01

## 变更摘要

`_onScrubEnd`：cancel debounce 后立刻 seek `_scrubTarget`，并乐观将 `_position` 同步为目标再结束 scrub，避免拇指回弹到拖动起点。

## 验证

- [x] `flutter analyze lib/player/cine_video_controls.dart` 无 error
- [ ] 冒烟：拖进度条松手拇指不回起点（用户）

## 回滚

恢复 `_onScrubEnd` 仅 `setState(() => _isScrubbing = false)`。
