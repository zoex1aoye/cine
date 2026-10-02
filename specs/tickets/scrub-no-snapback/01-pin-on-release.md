# 01 松手钉住 scrub 目标
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261001-07
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

`CineVideoControls._onScrubEnd`：cancel debounce 后立刻 seek `_scrubTarget`，并把 `_position` 同步为目标再结束 scrub。

## 验收

- [x] `_onScrubEnd` 调用最终 `_seekMain(_scrubTarget)`
- [x] 结束 scrub 前 `_position = _scrubTarget`
- [x] `flutter analyze` 相关文件无 error
- [ ] 冒烟：拖进度条松手不回起点（用户）
