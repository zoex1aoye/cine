# 20261002 — 测速前 3 条后早开播

- PRD：`PRD-20261002-01`
- Tickets：`specs/tickets/early-play-after-n-probes/01`
- 日期：2026-10-02

## 变更摘要

`_runSpeedTest`：本轮新测线路先并行测前 3 条，结束后 `SourcePicker` 早 init；首批无可用则逐条续测至可用；已开播后其余并行续测，未点播放可 upgrade；Champion / 点播放 abort 保留。

## 验证

- [x] `flutter analyze lib/pages/player_page.dart` 无 error
- [ ] 多线路冷启动冒烟：前 3 测完可进播放态（用户）

## 回滚

恢复对全部 pending 一次 `Future.wait` 后再 `_applyRecommendedSource`。
