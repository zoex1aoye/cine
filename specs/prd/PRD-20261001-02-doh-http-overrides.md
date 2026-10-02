# PRD-20261001-02 — DoH 引导的 HTTP 连接（C1）

| 字段 | 值 |
|---|---|
| 编号 | PRD-20261001-02 |
| 档位 | 中型 × 碰 API / 跨平台 Dart IO |
| 栈位 | api |
| 状态 | 实现中 |

## 要解决什么问题

Clash TUN / fake-ip 下，Flutter Dart `HttpClient` 系统 DNS 解析失败（`Failed host lookup`），而系统 `dig`/`curl` 正常；仅换 API 根域无法兜底（发现链路同源失败）。

## 用户故事

作为 macOS（及同样 DNS 异常）用户，在开启 Clash 虚拟网卡时，我仍能完成详情/搜索等 API 请求，而不必改 Clash 配置或强制 App 走 7890 代理。

## 验收

- [x] `HttpOverrides` 创建的 `HttpClient` 对非 IP 主机经 DoH 解析后再 `Socket` 连 IP；URI 主机名不变（TLS SNI 仍为域名）
- [x] DoH 引导优先使用 **IP 字面量** 端点（避免鸡生蛋）
- [x] DoH 全失败时回退系统 `InternetAddress.lookup` / `Socket.startConnect(host)`
- [x] `JpApi` 共享 `HttpClient` lazy 创建，不早于 `HttpOverrides.global` 赋值
- [x] 现有 DNS 根域 failover 保留
- [x] `flutter analyze` 无 error；相关单测通过

## ATDD

| 场景 | 期望 |
|---|---|
| 主机名为 IPv4/IPv6 字面量 | 直连，不走 DoH |
| DoH 返回 A + CNAME | 使用 A（优先 IPv4）建连 |
| DoH 全失败 | 回退系统解析 |
| 解析结果缓存 | TTL 夹在 60–600s，命中不重复打 DoH |

## 决策记录

| 决策 | 选择 | 备注 |
|---|---|---|
| 方案 | C1 | 全局 `HttpOverrides`，非仅 jp_api 注入 |
| DoH 端点顺序 | 阿里 223.5.5.5/223.6.6.6 → 腾讯 1.12.12.12/120.53.53.53 → CF 1.1.1.1 兜底 | 均为 IP 字面量 |
| 不做代理 | 否 A | 不强制 7890 |
| 播流 DNS | 不做 | mpv/media_kit 另栈，本 PRD 不含 |

## 实现约束

- `.cursor/rules/execution-discipline.mdc`
- `.cursor/skills/cine-flutter-dev`
- AGENTS：密钥/签名口径不变；禁止写死本机绝对路径

## 不做的事

- Clash 配置教程作为功能依赖
- mpv / 播放地址 DoH
- 关闭证书校验以外的安全模型变更（维持现有 `badCertificateCallback`）
