# 2026-10-01 — DoH HTTP 连接引导（C1）

- PRD: `PRD-20261001-02`
- Ticket: `specs/tickets/doh-http-overrides/01-doh-connection-factory.md`

## 变更

- 新增 `lib/api/doh_dns.dart`：IP 字面量 DoH（阿里 223.5.5.5/223.6.6.6 → 腾讯 1.12.12.12/120.53.53.53 → CF 1.1.1.1 兜底）+ TTL 缓存
- **修复**：`connectionFactory` 必须自行 `SecureSocket.secure`（Dart 不会再升级）；否则 HTTPS 明文打 443 → 400，域名发现全失败、「没有分类数据」
- `main.dart`：`HttpOverrides` 全局 `connectionFactory`；bootstrap client 在 overrides 前 `install`
- `jp_api.dart`：CDN 用 `HttpClient` 改为 lazy，避免错过 factory
- 保留既有 API 根域 DNS failover
- `probeOrigin` 对非 200 / 非 code=1 补日志

## 验证

- `dart analyze`（相关文件无 error）
- `flutter test test/doh_dns_test.dart test/jp_domain_discovery_test.dart`
