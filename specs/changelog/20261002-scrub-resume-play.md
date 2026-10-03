# 拖进度条松手后恢复播放
- 日期：2026-10-02
- PRD：PRD-20261002-06
- Tickets：`specs/tickets/scrub-resume-play/01`

## 变更摘要
- 拖动中不再主动 `pause()`（避免 Android media_kit pause+seek 竞态松手后停住）
- 每次手势记录 `_wasPlayingBeforeScrub`；松手 seek 后若拖前在播则强制 `play()`
- seek epoch 防止拖动中的 in-flight seek 覆盖松手后的 play

## 验证
- [x] `flutter analyze lib/player/cine_video_controls.dart` 无 error
- [ ] 实机：播放中拖进度条松手应继续播（用户/Fire HD）
