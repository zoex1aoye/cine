# 2026-10-14 · 电影卡片底部 Scrim 叠字

- PRD：`PRD-20261014-01`
- 票：`specs/tickets/movie-card-scrim-footer/01-scrim-overlay.md`

## 变更

- `MovieCard` 去掉独立实心底栏，封面铺满 2:3
- 底部约 30% 半透明渐变 scrim 上叠标题/副标题（方案 B，无 blur）
- 评分、进度条、桌面悬停、移动删除、TV 焦点行为保持
- 叠字水平居中；标题/副标题字号与内边距随卡片宽度缩放（约 10–16 / 8.5–13）

## 验证

- `flutter analyze lib/widgets/movie_card.dart`
- `flutter test test/tv_surface_card_test.dart`
- Linux 桌面首页 / 历史页截图
