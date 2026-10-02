# 20261001 — 缓冲圈显示加载速度

- PRD：`PRD-20261001-08`
- Tickets：`specs/tickets/buffer-speed-hud/01`
- 日期：2026-10-01

## 变更摘要

播放中缓冲 ≥~0.8s 后，转圈下方显示「加载中 {速度|—}」（轮询 mpv `cache-speed`）；移除「网络较弱，缓冲中…」。

## 验证

- [x] `flutter analyze lib/player/cine_video_controls.dart` 无 error
- [ ] 冒烟：seek/卡顿缓冲可见速度行（用户）

## 回滚

恢复弱网提示条；去掉 cache-speed 轮询与速度 HUD。
