# 20261001 — 播放窗桌面 hover 唤出控件

- PRD：`PRD-20261001-05`
- Tickets：`specs/tickets/player-hover-controls/01`
- 日期：2026-10-01

## 变更摘要

桌面播放区：鼠标进入/移动显示 `CineVideoControls`，移出立刻隐藏，播放中静止约 3s 自动隐藏；单击改为播停；触控仍点按切换显隐；双击 seek 保留。

## 验证

- [x] `flutter analyze` 相关文件无 error
- [ ] macOS 冒烟：进区出控件、离区立刻藏、3s 藏、单击播停

## 回滚

恢复 `cine_video_controls.dart` 仅 `onTap: _toggleControls`。
