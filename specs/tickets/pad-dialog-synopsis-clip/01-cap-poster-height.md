# 01: 竖排布局海报高度封顶 220

- PRD：PRD-20261003-01
- 装载技能：cine-flutter-dev

## 任务

`lib/widgets/movie_info_dialog.dart` 非宽屏分支：`AspectRatio(16/9)` 海报改为
`SizedBox(height: math.min((width - margin) * 9 / 16, UIAdapt.px(context, 220)))`，
`posterWidget()` 内 `FailoverCoverImage` 已是 `BoxFit.cover`，无需改裁切。

## 验收

- [x] `flutter analyze lib/widgets/movie_info_dialog.dart` 无 error
- [x] 实机（pad 逻辑宽 600）：弹窗简介可见 ≥3 行
- [ ] 手机回归：弹窗显示与改动前一致
