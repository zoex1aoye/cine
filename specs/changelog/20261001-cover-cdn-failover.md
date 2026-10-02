# 2026-10-01 — 封面 CDN 失败换域

- PRD：PRD-20261001-03
- Tickets：`specs/tickets/cover-cdn-failover/01`、`02`

## 变更

- 新增 `lib/utils/cover_cdn.dart`：候选域合并、封面 URL 拼装/换 host、步进下一候选
- `JpApi` / `MubuApiClient` 暴露 `imgDomainCandidates`；`_loadConfig` 始终拉 package 列表并合并硬编码备份（不改单测速图选主）
- 新增 `FailoverCoverImage`：加载失败按候选顺序换域；`CoverDomainSessionCache` 会话内记住成功域
- 接入列表卡片、详情弹窗、首页 banner、播放页海报位
- 单测：`test/cover_cdn_test.dart`

## 验证

- [x] `flutter test test/cover_cdn_test.dart`
- [x] `flutter analyze` 无 error
- [ ] macOS 冒烟：电影筛选页原灰卡（如蜡笔小新）出图
