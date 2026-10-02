# 01 抬升全屏顶栏命中层
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261001-06
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

`CineVideoControls`：全屏顶栏（返回键）移到中间播控之上；返回键加大可点热区；`onPressed` 与底栏一致（全屏时 `exitFullscreen`）。

## 验收

- [x] 顶栏在 Stack 中位于 Center 之后（更高 z-order）
- [x] 返回热区明确可点，不依赖渐变条空白吞事件
- [x] 全屏返回仅 `exitFullscreen`，无页面 `Navigator.pop`
- [x] `flutter analyze` 无 error
- [ ] 安卓冒烟：全屏左上角返回只退全屏（用户）
