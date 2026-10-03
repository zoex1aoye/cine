# 04 TV 浏览态焦点
- 状态： [x] 完成
- PRD：PRD-20261002-05
- 依赖：01
- 栈位：ui
- 须装载：cine-flutter-dev

## 交付什么
`CineSurface.tv` 下首页导航与影片网格可用 D-pad 聚焦并激活；焦点环可见。

## 验收
- [x] TV 下导航项 / MovieCard 可聚焦；Select/Enter 触发原点击
- [x] 焦点样式可见（ring 或 scale）
- [x] mobile surface 不强制焦点漫游
- [x] 对话框主按钮 TV 下 autofocus；Back 可关
- [x] `flutter analyze` 无 error

## 笔记
复用 MubuButton Focus 模式；网格行列遍历。
