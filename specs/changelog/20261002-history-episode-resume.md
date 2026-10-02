# 20261002 — 播放历史剧集恢复

- PRD：`PRD-20261002-03`
- Tickets：`specs/tickets/history-episode-resume/01`、`02`
- 日期：2026-10-02

## 变更摘要

测速/早开播前软锁定 `lastEpisodeName`，`_episodeScopeRef` / `_applyRecommendedSource` 优先历史集（用户手动换集前）；已错误 init 时硬匹配并 `_switchSource`。历史卡片副标题优先显示上次集名；电影全局选线不变。

## 验证

- [x] `flutter analyze` 相关文件无 error（既有 warning/info 仍在）
- [x] `flutter test test/episode_utils_test.dart` 全部通过
- [ ] 冒烟：播电视剧到非第1集 → 历史再进应对集+进度；电影行为不变；历史卡片见集名（用户）

## 回滚

撤销 `player_page` 软锁/scope 改动、`episode_utils` 新 helper、历史 `showSubtitle` 与卡片集名优先逻辑。
