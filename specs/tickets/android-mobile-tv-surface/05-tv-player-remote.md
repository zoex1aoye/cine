# 05 TV 播放器遥控
- 状态： [x] 完成
- PRD：PRD-20261002-05
- 依赖：04
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么
TV surface 播放页：左右 seek、上下音量、OK 播放暂停、Back 退出；按键唤出控件条。

## 验收
- [x] 仅 `isTvSurface` 启用遥控键位映射
- [x] 键位符合上表；控件条按键时显示并沿用 hide timer
- [x] mobile / 桌面原快捷键与手势不受损
- [x] `flutter analyze` 无 error

## 笔记
改 cine_video_controls / player_page Shortcuts，守内部全屏语义。
