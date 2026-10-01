# 02 共用封面失败换域组件并接到列表/详情/播放

- 状态： [x] 完成
- PRD：PRD-20261001-03
- 依赖：01
- 栈位：ui（+ 轻触 api 读取候选）
- 须装载：cine-flutter-dev

## 交付什么

列表卡片、详情弹窗、播放页海报共用一套封面加载：主域失败后按候选顺序换域；会话内记住 `coverPath → 成功域`；全失败保持现网灰底电影图标。

## 验收

- [x] 抽出可复用封面 Widget（`FailoverCoverImage`），读取 `imgDomain` + `imgDomainCandidates`
- [x] 失败判定：`errorWidget` 触发（含 403 / 建连失败）后换下一候选
- [x] 按候选顺序换下一 URL；成功则写入会话缓存，重建同 path 直接从成功域起
- [x] 接入：`MovieCard`、`movie_info_dialog`、首页 banner、播放页背景/模糊底/前景海报
- [x] 全候选失败 → 现有灰底 `Icons.movie`（播放页部分位为 shrink/纯色，与原行为一致）
- [x] 空 `coverPath` / 空 `imgDomain` 与现网一致
- [ ] macOS 冒烟：电影筛选页原稳定灰卡能出图（待本机跑 App 确认）
- [x] `flutter analyze` 无 error（仅既有 info）

## 笔记

- `lib/widgets/failover_cover_image.dart` + `CoverDomainSessionCache`
- 换域用 `ValueKey(_url)` 强制重载，避免坏缓存键
