# PRD-20261001-03 — 封面 CDN 失败换域

| 字段 | 值 |
|---|---|
| 编号 | PRD-20261001-03 |
| 确认人 | 用户（2026-10-01 口径 1A/2A/3A/4A/5A） |
| 档位 | 中型 × 碰 API / 共享封面组件 |
| 栈位 | api + ui |
| 状态 | 已实现，待 macOS 冒烟确认 |

## 要解决什么问题

封面 `coverPath` 均为相对路径，拼到当前 `imgDomain` 后加载。启动竞速用**单张测速图**选主域（抽样日为 `static.bjynj.com`），该镜像对约半数对象返回 OSS `403 AccessDenied`（XML，非图），列表/详情/播放页同一 URL 稳定灰占位。同一 path 在备用域（如 `static.hzkqw.com`）可 200 出图。需要在**单张封面加载失败时按备用域顺序换域重试**，不改启动竞速选主域。

## 用户故事与验收标准

作为浏览片库的用户，当某张海报在当前图片 CDN 上 403/非图/连不上时，客户端应自动改用备用图片域再试，以便多数缺图卡片能显示真实海报，而不必等源站修镜像。

- [ ] 列表卡片、详情弹窗、播放页海报走**同一套**封面加载（失败换域）逻辑
- [ ] 换域候选 = `packageDomainConfig` 的 `imgDomain` 列表 ∪ 现有硬编码备份（`static2.gutaike.com`、`static.shaxyt.com`），去重；当前主域优先，失败后**按列表顺序**试下一个
- [ ] 判定失败：HTTP 非 2xx、建连失败、Content-Type 非 `image/*`（含 `application/xml` 的 AccessDenied）
- [ ] 全部候选失败 → **保持现有**灰底 `Icons.movie` 占位，不加文案
- [ ] 成功域名对本 `coverPath` **会话内记住**，同卡重建不重复从失败域打起
- [ ] 空 `coverPath` / 空 `imgDomain` 行为与现网一致（空域转圈、无 path 走 error 占位）
- [ ] macOS 冒烟：电影筛选页能看到原先稳定灰卡（如「蜡笔小新：灼热的春日部舞者们」）出图或明确仍全域失败
- [ ] `flutter analyze` 无 error；相关单测覆盖 URL 换域与失败判定

## ATDD

| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 主域 403、备用 200 | path 在 A 上 403 XML、在 B 上 200 image/jpeg | 网格渲染该卡 | 显示 B 上的图，不长期停在 errorWidget |
| 主域 200 | path 在当前 `imgDomain` 正常 | 渲染 | 不打备用域（或可忽略探测） |
| 全候选失败 | 所有候选均非图或网络失败 | 渲染 | 现有灰底电影图标 |
| 空 path | `coverPath` 空 | 渲染 | 不发起换域；与现网空 URL 一致 |
| 会话记忆 | 某 path 已在 B 成功 | 滑出再滑回 / 进详情 | 直接用 B，不先闪 A 的 403 |
| 绝对 URL | path 已是 `http(s):`（含旧 `bqxqqqnf.top` 改写） | 渲染 | 先按现有 `coverUrl` 规则；失败后再把 **host** 换成候选域、**path 不变** |
| 启动竞速 | 冷启动选主域 | 打开 App | 仍用单测速图竞速；本 PRD 不改选主逻辑 |

## 范围

| 含 | 不含 |
|---|---|
| 封面网络图加载失败换域 | 改 `_raceImgDomains` / 多图抽样选主域 |
| 列表、详情、播放页海报 | 播放 HLS、字幕、非封面图片 |
| 暴露/复用备用 `imgDomain` 列表 | 新封面专用域名配置 |
| 失败占位维持现网 | 「封面暂不可用」文案、重试按钮 |
| macOS 验收 | 强制 iOS/Android/Windows 本迭代验收 |
| 会话内 path→成功域缓存 | 持久化 Hive 封面域映射 |

## 关键数据流

1. `JpApi._loadConfig` 仍选出单一 `_imgDomain` 作为默认主域，并**保留完整候选列表**（配置 ∪ 硬编码，去重，主域置首）。
2. `VideoItem.coverUrl(domain)` 继续负责相对路径拼接与 `bqxqqqnf.top` 改写。
3. 封面 Widget 用主域 URL 走 `CachedNetworkImage`（或等价）；`errorWidget` / 非图判定触发后，按候选顺序构造下一 URL 再加载。
4. 任一候选 200 且 `image/*` → 展示，并写入会话缓存 `coverPath → domain`。
5. 列表耗尽 → 现网 error 占位。

## 决策记录

| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | MVP 边界 | 仅单图失败换域，不改启动竞速 | 根因是镜像对象不全，不是主域完全不可达；测速图在坏镜像上仍 200 | 2026-10-01 |
| 2 | 换域策略 | 候选列表顺序试到成功或耗尽 | 实现简单、请求可控；诊断日顺序重试即可救回抽样 403 | 2026-10-01 |
| 3 | 空态 | 全失败保持灰底电影图标 | 不引入新文案 | 2026-10-01 |
| 4 | 验收平台 | macOS 冒烟 | 当前主环境 | 2026-10-01 |
| 5 | 备用域来源 | `packageDomainConfig` + 现有硬编码 | 与 CDN 配置同源，不另维护列表 | 2026-10-01 |

## 风险与回滚

| 风险 | 缓解 |
|---|---|
| 网格中大量 403 导致串行打多个 CDN、卡顿/费流量 | 顺序短超时；会话缓存成功域；同一 URL 并发只飞一次 |
| `cached_network_image` 把 403 XML 当可缓存失败 | 换域后必须换 URL；失败项勿污染成功 URL 缓存 |
| 候选列表为空（配置未拉到） | 至少含当前 `imgDomain` + 硬编码备份 |
| 回滚 | 关闭换域，封面仍只绑 `imgDomain`；API 选主逻辑未改，回滚面小 |

## 实现约束

- 引用：`.cursor/rules/flutter-structure.mdc`、`.cursor/rules/execution-discipline.mdc`
- 须装载技能：`cine-flutter-dev`、`implement`、`code-review`
- AGENTS：签名/密钥不变；禁止写死本机绝对路径；`MubuApiClient.instance` 测试须先赋值
- `coverUrl` 在 `lib/models/jp_models.dart` 与 `lib/models/mubu_models.dart` 重复，换域规则两处须一致或抽一处

## 不做的事

- 启动 CDN 竞速改为多封面抽样选主域
- 为封面失败增加提示文案或手动重试按钮
- Hive 持久化每张封面的成功域名
- 播放内核 / 非封面资源换域
- 本迭代强制全平台回归
