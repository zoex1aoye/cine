# 01 测速/早开播锁定历史集
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261002-03
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

从历史进电视剧时，测速代表源、Champion、早开播选线全程锁定 `lastEpisodeName`，并在已错误 init 时切回历史集；点播放仍 seek 进度。电影全局选线不变。

## 验收
- [x] `_runSpeedTest` 前软应用 saved 集（`requireProbed: false`）
- [x] `_episodeScopeRef` 在用户未手动换集前优先 `_savedEpisodeName`
- [x] `_applyRecommendedSource` 使用 `_episodeScopeRef` + `pickScopeEpisodeName`
- [x] 已 init 且当前集 ≠ saved：硬匹配后 `_switchSource`（未点播放）
- [x] 未 init：硬匹配后 init（既有路径）
- [x] 软匹配 / scope 优先有单测（抽 helper 时）
- [x] `flutter analyze` 无 error

## 笔记
根因：`_selectedSource` 默认 0 → scope 成第1集 → 早开播 init → 跳过 `_applySavedEpisodeSelection`。
