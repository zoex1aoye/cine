# 播放历史剧集恢复
- 编号：PRD-20261002-03 ｜ 确认人：用户 ｜ 档位：中型×碰播放器 ｜ 栈位：player + ui

## 要解决什么问题（1 段）

从播放历史进入电视剧时，早开播/Champion 路径以默认 `_selectedSource=0`（常为第1集）为 scope 选线并 init，随后因已 init 跳过 `_applySavedEpisodeSelection`，总落到第1集。需在测速/早开播全程锁定历史集数，并在锁定正确集后 seek 到上次进度；历史卡片展示上次剧集名。电影全局选线不变。存储字段已有，不改 Hive schema。

## 用户故事与验收标准
作为观众，我想要从历史继续看电视剧时直接回到上次那一集与进度，以便不用手动再选集。
- [x] 有 `lastEpisodeName` 的电视剧：测速代表源 / Champion / 早开播选线均锁定该集，再在集内选线（代码侧；冒烟待确认）
- [x] 锁定正确集后点播放，仍 seek 到 `lastPositionMs`（既有 `_playbackStartPositionMs`）
- [x] 早开播若已 init 到错误集：测速结束后、未点播放前硬匹配并 `_switchSource` 到历史集（代码侧）
- [x] 历史 Tab 卡片副标题优先显示 `lastEpisodeName`；无则回退 year • category（代码侧）
- [x] 电影 / 类电影源（`isFilmStyleSources`）仍全局选线，行为不变（`pickScopeEpisodeName` 空 scope）
- [x] 收藏列表副标题仍不展示（`showSubtitle: false`）

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 历史复进剧集 | 历史有第05集 + 进度 | 从历史进播放页 | 选中第05集；点播放 seek 到进度 |
| 早开播兜底 | 缓存/早开播曾落到第1集 | 测速结束且未点播放 | 自动切到历史集 |
| 电影 | 电影多线路、无「第N集」 | 进播放页 | 全局选线，不按集锁 |
| 历史卡片 | `lastEpisodeName=第05集` | 打开历史 Tab | 卡片副标题为「第05集」 |
| 收藏不变 | 收藏列表 | 打开收藏 Tab | 无副标题（或既有行为） |
| 手动换集 | 进页后用户点选集数 | 换到另一集 | scope 跟用户所选，不再强锁 saved |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | 测速/早开播 scope | 1A 锁定历史集再选线 | 根因在 scope 用第1集 | 2026-10-02 |
| 2 | 进度 | 2A 对集后继续 seek | 既有字段与 seek 路径可用 | 2026-10-02 |
| 3 | 历史卡片 | 3A 显示上次集名 | 便于辨认续看位置 | 2026-10-02 |
| 4 | 电影 | 4A 全局选线不动 | `isFilmStyleSources` → 空 scope | 2026-10-02 |
| 5 | 软锁定时机 | 测速前软匹配（不要求 probed） | 让代表源/Champion 一开始就在正确集 | 2026-10-02 |

## 关键数据流
1. `_loadSavedProgress` → 写入 `_savedEpisodeName` / `_savedLineName` / position
2. sources 就绪后：`_applySavedEpisodeSelection(requireProbed: false)` 软锁 `_selectedSource`
3. `_runSpeedTest`：代表源与 `_applyRecommendedSource` 用 `_episodeScopeRef`（优先 saved，直至用户手动换集）
4. 测速结束：若已 init 且当前集 ≠ saved → 硬匹配 + `_switchSource`；若未 init → 硬匹配后 init
5. 点播放：`_playbackStartPositionMs` seek

## 范围
| 含 | 不含 |
|---|---|
| player_page 软/硬锁集 + scope 修复 | 改 Hive adapter / 新字段 |
| 历史卡片副标题集名 | 改 early-batch N=3 策略本身 |
| 软匹配/scope 纯函数单测（可抽） | 改收藏列表副标题 |

## 风险与回滚
- 风险：软锁后代表源 URL 与测速缓存 key 仍按线路级传播——与现网一致；若某集缺线则硬匹配回退既有三级逻辑
- 回滚：撤销 `player_page` scope/软锁改动与历史 `showSubtitle`；卡片副标题回退 year•category

## 实现约束
- 引用：`.cursor/rules/flutter-structure.mdc`、`.cursor/rules/player-discipline.mdc`
- 须装载技能：cine-flutter-dev
- 主路径：`lib/pages/player_page.dart`、`lib/widgets/movie_card.dart`、`lib/pages/home_page.dart`；可选 `lib/utils/episode_utils.dart`

## 不做的事
- 不改 Hive schema / TypeAdapter
- 不改测速 N=3 早开播策略本身
- 不改收藏列表副标题行为
