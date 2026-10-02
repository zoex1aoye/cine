# 01 scrub 松手恢复播放
- 状态： [x] 完成
- PRD：PRD-20261002-06
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么
`_onScrubEnd` 在拖动前为播放态时自动 `play()`；捕获拖前态时兼容 `player.state.playing`。

## 验收
- [x] 播放中拖松手继续播
- [x] 暂停中拖松手仍暂停
- [x] `flutter analyze lib/player/cine_video_controls.dart` 无 error

## 笔记
根因：`_onScrubStart` pause，恢复只在 `_returnToAnchor`。
