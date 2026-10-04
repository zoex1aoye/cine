# 01 — 首页分批出海报，跳过坏图片域

PRD：PRD-20261004-04

- [x] `HomeTagFeed`：板块列表先发布，手推晚到再合并
- [x] `CategoryContentView` 按板块 `setState`，子板块不再自己请求
- [x] `pickImgDomain` 并行探测，主域宽限 400ms
- [x] `_testImgDomain` 看响应头后断开
- [x] `CoverDomainSessionCache` 记录坏域；`FailoverCoverImage` 跳过
- [x] `DohDns` 并行查询并负缓存确定性失败
- [x] 单测：`home_hand_data_test`、`img_domain_probe_test`、`cover_cdn_test`、`doh_dns_test`
