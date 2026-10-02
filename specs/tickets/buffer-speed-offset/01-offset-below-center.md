# 01 缓冲 HUD 下移
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261002-03
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

`CineVideoControls` 缓冲指示由 `Center` 改为垂直偏下对齐，避开中心播控。

## 验收

- [x] 缓冲 HUD 不与中心播放按钮重叠
- [x] `flutter analyze` 无 error
