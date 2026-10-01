# 荐片 API 域名发现对齐与搜索精确优先
- 编号：PRD-20261001-01 ｜ 确认人：用户 ｜ 档位：中型×碰 API ｜ 栈位：api

## 要解决什么问题（1 段）

官包 5.0.4 已改为 OSS + DoH + 随机子域 + 日期盐的动态域名发现，签名 `version=504`；本仓仍固定三域名竞速且签名 `503`，易落到 `api.ipixiv.com` 等「能通但索引偏旧」的节点，导致新片/剧搜不到或排序异常。需对齐域名发现与签名，作废劣质域缓存，并在搜索结果中把精确标题排到前面。

## 用户故事与验收标准

作为幕布用户，我想要客户端连上与官包同类的新索引 API 节点，并在搜索时优先看到完全匹配的标题，以便能找到「兰香如故」「给阿嬷的情书」等新内容。

- [ ] 启动后不再把 `api.ipixiv.com` / `release.ipixiv.com` 当作有效 `last_api` 根域（已有缓存会被清除并重新发现）
- [ ] 无合法缓存时，按 OSS → DoH TXT → 日期盐兜底发现可用根域；保底含 `japi.zxfmj.com`
- [ ] 非 `japi.zxfmj.com` 的根域以 `https://{rand6}.{root}/api` 测活/建连；`japi.zxfmj.com` 直连不随机
- [ ] Hive 缓存粒度为**根域**（非带随机子域的完整 URL）；每次启动/测活对非常规 japi 根域重新随机子域
- [ ] 请求签名 Header `version=504`，`signature=MD5("504"+timestamp+secret)`
- [ ] `search()` 仍请求 `/v2/search/videoV2`；返回列表按「精确 title → 包含 title/original_name → 其余」稳定排序
- [ ] 不改系统代理行为；`flutter analyze` 无 error

## ATDD

| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 劣质缓存 | Hive 中 `last_api_root`（或旧 `last_api_domain`）指向 ipixiv/release | 启动 init | 清除劣质项，走发现流水线，最终 base 非劣质域 |
| OSS 发现 | 固定列表测活失败，OSS domain.txt 可达 | 发现 | 解析逗号分隔根域并测活，成功则写入根域缓存 |
| DoH 发现 | OSS 失败，DoH TXT `pyvemnlu.cc` 可达 | 发现 | 解析 TXT 中的根域列表并测活成功 |
| 日期盐 | 前序均失败 | 发现 | 用当日日期+盐生成 `*.com` 候选并测活 |
| 随机子域 | 根域为 `hzhnl.com` 类 | 测活 | 请求形如 `https://XXXXXX.hzhnl.com/api/v2/settings/appAuthConfig` |
| japi 特例 | 根域为 `japi.zxfmj.com` | 测活/建连 | `https://japi.zxfmj.com/api/...` 无随机前缀 |
| 签名 | secret 已拉取 | 任意需签名 GET | Header 含 version=504 与对应 MD5 |
| 搜索排序 | videoV2 返回含精确与模糊标题 | search(keyword) | 精确 title 条目排在包含匹配之前 |
| 代理 | 本机开着系统 VPN 代理 | 默认启动 | 行为与改前一致（不主动接系统代理） |

## 决策记录

| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | 域名发现深度 | 完全对齐桌面：OSS + DoH + 日期盐 | 官包 5.0.4 路径；仅止血无法跟上换域 | 2026-10-01 |
| 2 | 签名版本 | 固定 504 | 对齐桌面；实测搜索可用 | 2026-10-01 |
| 3 | 系统代理 | 不动 | 好域名直连/代理均通；非本次根因 | 2026-10-01 |
| 4 | 劣质缓存 | 硬编码作废 ipixiv / release | 能通但索引旧，会锁死体验 | 2026-10-01 |
| 5 | 搜索增强 | 精确优先排序；不做别名二次搜 | 控制范围；别名表难维护 | 2026-10-01 |
| 6 | 发现时机 | 首次/缓存失效全量；有合法根则后台静默刷新 | 平衡启动速度与新鲜度 | 2026-10-01 |
| 7 | 随机子域 | 每次测活新随机；缓存只存根域 | 对齐官包 localStorage 语义 | 2026-10-01 |
| 8 | 质量探针 | 不做连通外的抽样搜 | 3a；降低复杂度 | 2026-10-01 |
| 9 | 代码落位 | `jp_domain_discovery.dart` + `JpApi` 消费 | 4b；控制 `jp_api.dart` 体积 | 2026-10-01 |

## 范围

| 含 | 不含 |
|---|---|
| 域名发现模块、根域缓存迁移、504 签名 | 系统代理探测/开关 |
| 搜索结果客户端排序 | `/search/searchList`、别名二次请求 |
| 劣质域硬编码黑名单 | 搜索关键词质量探针 |
| 与现有 img CDN / secret init 衔接 | UI 大改、播放器改动 |

## 关键数据流

1. `JpDomainDiscovery.resolve()` → 根域字符串  
2. `JpApi`：`baseUrl = buildBaseUrl(root)`（含本会话随机子域）→ `_loadConfig` / 业务 `_get`  
3. `search`：解析 `data` 为 List → 排序 → `VideoItem`

## 风险与回滚

| 风险 | 缓解 | 回滚 |
|---|---|---|
| DoH/OSS 在部分网络不可达 | 保留 japi 保底；多 DoH；日期盐 | 临时把发现短路为仅 `japi.zxfmj.com` |
| 随机子域 DNS 失败率高 | 同根域多次随机重试；换下一根域 | 对已知根域尝试无前缀或固定前缀（需另开决策） |
| 旧 key `last_api_domain` 全 URL 与新根域并存 | 迁移/解析兼容一层后写新 key | 清 config box 相关键 |

## 实现约束

- 引用：`.cursor/rules/flutter-structure.mdc`、`.cursor/rules/execution-discipline.mdc`
- 须装载技能：`cine-flutter-dev`、`implement`
- API 签名口径对照现有 `lib/api/jp_api.dart`，仅将版本常量改为 504；密钥不入库明文文档
- 禁止写死本机绝对路径；临时探测脚本不进仓库

## 不做的事

- 不实现系统代理自动选择  
- 不维护影片别名表、不自动二次搜索  
- 不接入 TV APK 热更域（ubj83 等已证实不可用）  
- 不在本 PRD 改播放器 / UI 视觉  
