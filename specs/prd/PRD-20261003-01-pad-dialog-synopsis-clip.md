# PRD-20261003-01: pad 详情弹窗简介被裁切

## 背景

Android pad（800×1280，dpr≈1.33，逻辑宽 ≈600）上打开影片详情弹窗，剧情简介只显示不到一行且被硬切。

## 根因

`movie_info_dialog.dart` 竖排布局（`isWide = width >= 650` 为 false）下：
- 弹窗固定高 `px(540)`，海报 `AspectRatio(16/9)` 占满宽度 → 弹窗宽 560 时海报高 ≈315
- 内容区仅剩 225 − padding 40 = 185px，扣掉标签/标题/按钮等固定 ≈170px
- 简介 `Expanded` 只分到 ≈15px（约半行）

## 用户故事

作为 pad 用户，我在详情弹窗里能读到至少 3 行剧情简介。

## 验收标准

- pad（逻辑宽 600）上详情弹窗海报高度不超过 220，剧情简介可见 ≥3 行
- 手机（逻辑宽 390）显示与改动前一致（390×9/16≈219 < 220，不受影响）

## 方案

竖排布局海报高度封顶：`AspectRatio(16/9)` 改为 `SizedBox(height: min(宽×9/16, 220))` + `BoxFit.cover` 裁切。

## 影响

- 文件：`lib/widgets/movie_info_dialog.dart`（仅非宽屏分支）
- 不触碰 player / api / 共享组件
