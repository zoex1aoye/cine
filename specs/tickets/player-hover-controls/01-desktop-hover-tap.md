# 01 桌面 hover 显隐 + 单击播停
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261001-05
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

`CineVideoControls`：桌面指针进入/移动显示控件、离开立刻藏、3s 静止藏；单击改为播停；触控点按切换不变；双击 seek 保留。

## 验收

- [x] MouseRegion 覆盖播放区含底栏
- [x] 桌面 onTap → play/pause；非桌面 onTap → toggle 控件
- [x] 离开立刻隐藏；显示时 `_startHideTimer`（播放中且非 scrub）
- [x] 区内 pointer hover 重置 hide timer
- [x] `flutter analyze` 无 error
- [ ] macOS 冒烟勾选（用户）

## 笔记

README「鼠标与界面操作」已对齐。
