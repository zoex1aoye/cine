## 2026-10-01 — 荐片 API 域名发现对齐与搜索精确优先
- PRD / Tickets：PRD-20261001-01 · `specs/tickets/jp-api-domain-discovery/{01,02,03}`
- 摘要：对齐桌面 5.0.4 的 OSS/DoH/日期盐根域发现与签名 `504`；作废 `api.ipixiv.com` / `release.ipixiv.com` 缓存；搜索结果精确标题优先，避免落到旧索引节点导致新片搜不到。
- 验证：`dart analyze` 无 error；`flutter test` 本机曾因 SDK `pub get` 拉 git 挂起未完整跑通，待本机重试 + 搜索冒烟（兰香如故 / 给阿嬷的情书）
- 规范飞轮：无（`cine-flutter-dev` 仍写「只改 jp_api」——若再改发现逻辑建议改口为「jp_api + jp_domain_discovery」）
