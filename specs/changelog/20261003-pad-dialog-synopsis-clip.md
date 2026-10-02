# pad 详情弹窗简介被裁切

- 日期：2026-10-03
- PRD：PRD-20261003-01
- Tickets：`specs/tickets/pad-dialog-synopsis-clip/01`

## 变更摘要
- `movie_info_dialog.dart` 竖排布局海报高度封顶 220（`min(宽×9/16, 220)` + cover 裁切）
- 根因：pad（逻辑宽 600）上 16:9 海报随宽度等比放大至 ≈315 高，固定弹窗高 540 内简介 `Expanded` 只剩 ≈15px

## 验证
- [x] `flutter analyze lib/widgets/movie_info_dialog.dart` 无 error
- [x] 实机：pad 详情弹窗简介 ≥3 行（800×1280 pad 实测简介完整可见约 6 行）
- [ ] 手机回归无变化（计算上 390×9/16≈219 < 220 不受影响，未实测）
