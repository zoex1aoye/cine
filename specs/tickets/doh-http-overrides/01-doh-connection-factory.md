# 01 — DoH connectionFactory（C1）

| 字段 | 值 |
|---|---|
| PRD | PRD-20261001-02 |
| 状态 | [x] |
| 须装载 | `cine-flutter-dev` |

## 做啥

1. 新增 `lib/api/doh_dns.dart`：DoH JSON 查询、缓存、lookup API
2. `MyHttpOverrides` 挂 `connectionFactory`
3. `JpApi` 共享 HttpClient 改为 lazy
4. 单测：JSON 解析 / TTL 夹取 / IP 字面量短路
5. analyze + 相关 test；打 macOS 包供验 Clash TUN

## 验收

- [x] 见 PRD 验收项
- [x] 代码路径不要求用户改 Clash

## 完成勾选

实现并通过验证后将本票状态改为 `[x]`。
