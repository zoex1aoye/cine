# 01 暴露图片 CDN 候选列表与换域 URL

- 状态： [x] 完成
- PRD：PRD-20261001-03
- 依赖：无
- 栈位：api
- 须装载：cine-flutter-dev

## 交付什么

`JpApi` / `MubuApiClient` 暴露去重后的图片域候选（主域置首），并提供按候选域生成封面 URL 的纯函数；单测覆盖拼接、host 替换与列表去重置首。

## 验收

- [x] `_loadConfig` 在选出 `_imgDomain` 同时保留候选：`packageDomainConfig.imgDomain` ∪ 硬编码 `static2.gutaike.com` / `static.shaxyt.com`，去重；若默认域可用也并入候选
- [x] `MubuApiClient`（及实现）新增只读 `List<String> imgDomainCandidates`；主域恒为第一项；列表为空时至少含当前 `imgDomain`（若非空）+ 硬编码
- [x] 统一/对齐 `coverUrl`：相对路径 `https://$domain$path`；绝对 URL 仅替换 host（保留 path/query），并保留 `bqxqqqnf.top` → `static2.gutaike.com` 改写
- [x] 提供「给定 coverPath + 候选列表 + 起始下标 → 下一 URL/域」的可测纯逻辑（`lib/utils/cover_cdn.dart`）
- [x] 单测：去重置首、相对/绝对换域、空 path 返回空（`test/cover_cdn_test.dart`）
- [x] `flutter analyze` 无 error；`flutter test` 相关用例通过
- [x] **不改** `_raceImgDomains` / 单测速图选主逻辑

## 笔记

- 落地：`lib/utils/cover_cdn.dart`；`JpApi` 始终拉 package 列表合并候选
