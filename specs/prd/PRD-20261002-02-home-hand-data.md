# 首页板块前置运营手推片
- 编号：PRD-20261002-02 ｜ 确认人：用户 ｜ 档位：小修×碰 API ｜ 栈位：api

## 要解决什么问题（1 段）

首页「近期热播」等板块只拉 `pc_dyTag/tpl*_list`，缺官方 `/dyTag/hand_data` 前置，列表偏旧。按桌面 5.0.4：第 1 页把该 tag 的 hand_data 插到最前再截断。

## 用户故事与验收标准
作为观众，我想要首页热播板块看到运营刚推的新片，以便和官方客户端一致。
- [x] 分类页并行请求 `getHomeHandData(categoryId)`（代码侧；冒烟待确认）
- [x] 各 tag 第 1 页：`hand + tpl` 去重后截到 count
- [x] hand_data 失败不影响 tpl 列表展示
- [x] 查看全部第 1 页同样前置（传入 categoryId）

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 有手推 | tag 在 hand_data 中 | 打开首页 | 该板块前排含手推片 |
| 无手推 | tag 不在 map | 打开首页 | 仅 tpl 列表 |
| 接口失败 | hand_data 报错 | 打开首页 | 仍显示 tpl |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | 数据源 | `/dyTag/hand_data?category_id=` | 官方 Category 页 | 2026-10-02 |
| 2 | 合并 | 仅 page=1 前置 + 按 id 去重 | 对齐官方并避免重复卡 | 2026-10-02 |

## 实现约束
- 引用：`.cursor/rules/flutter-structure.mdc`
- 须装载技能：cine-flutter-dev
- 签名仍走现有 `_get`，不改盐

## 不做的事
- 不接 `/weekRank/*`（那是周榜页）
- 不改 `pc_dyTag` 主路径
