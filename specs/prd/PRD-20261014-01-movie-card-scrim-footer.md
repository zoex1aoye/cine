# 电影卡片底部 Scrim 叠字
- 编号：PRD-20261014-01 ｜ 确认人：用户 ｜ 档位：中型×共享组件 ｜ 栈位：ui

## 要解决什么问题（1 段）

`MovieCard` 现为「2:3 封面 + 实心底栏」两段式，底栏与海报割裂。用户选定方案 **B：底部 Scrim（半透明渐变带）叠字**，去掉独立底栏，标题/副标题叠在封面底部约 30% 的 scrim 上；不用高斯模糊（方案 A），以利滚动列表性能。

## 用户故事与验收标准
作为浏览用户，我想要卡片标题叠在海报底部的暗带上，以便封面与文字一体、列表滚动更省。
- [x] 卡片外观为单一 2:3 海报面，无独立实心 footer
- [x] 底部约 30% 为 scrim（透明→深色渐变），白字标题 + 可选副标题叠其上
- [x] 评分角标、播放进度条、桌面悬停按钮、移动端删除、TV 焦点红框行为保持
- [x] 副标题规则不变：`showSubtitle` / `lastEpisodeName` / 年·类拼接
- [x] `flutter analyze` 无 error；既有 TV 焦点相关测试通过

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 有副标题 | year+category 非空 | 渲染卡片 | 海报底部叠标题与「年 · 类」；无独立底栏 |
| 历史集名 | `showSubtitle` 且 `lastEpisodeName` 非空 | 渲染卡片 | 副标题为集名 |
| 无副标题 | year/category/集名皆空或 `showSubtitle=false` | 渲染卡片 | 仅标题叠在 scrim 上 |
| TV 焦点 | `CineSurface.tv` | 获焦 + ActivateIntent | 红框出现且触发 onPlay |
| 低端档 | `DeviceProfile` constrained | 渲染网格 | 仍无 BackdropFilter 糊带；悬停桌面模糊可保留 |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | A 磨砂 vs B Scrim | **只做 B** | 用户看真实海报后明确选 B | 2026-10-14 |
| 2 | 早期「外观 A / 性能兜底 B」 | 作废，改为 B 为唯一实现 | 用户改口 | 2026-10-14 |
| 3 | Scrim 高度 | **约 30%** 封面高 | 与已评原型一致；长标题仍单行 ellipsis | 2026-10-14 |
| 4 | 是否按设备档降级到更淡 scrim | 否，全档统一 B | 简化；B 本身无 blur 成本 | 2026-10-14 |

## 实现约束
- 引用：`.cursor/rules/flutter-structure.mdc`
- 须装载技能：cine-flutter-dev
- 主改：`lib/widgets/movie_card.dart`；网格布局已按内容高度排布，勿写死含 footer 的总高

## 不做的事
- 不做方案 A（BackdropFilter 底部糊带）及 A/B 运行时切换
- 不改评分字段来源、不新增清晰度角标
- 不改 `MovieSliverGrid` 列数/请求条数
- 不改桌面悬停全卡 BackdropFilter 按钮层（与底部 scrim 无关）
