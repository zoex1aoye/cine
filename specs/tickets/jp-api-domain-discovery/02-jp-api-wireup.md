# 02 JpApi 接入根域缓存、劣质域作废与 504
- 状态： [x] 完成
- PRD：PRD-20261001-01
- 依赖：01
- 栈位：api
- 须装载：cine-flutter-dev

## 交付什么

`JpApi` 消费域名发现：Hive 缓存根域、启动作废劣质域、会话内拼 baseUrl、签名改为 504，后台静默刷新仍走发现。

## 验收

- [x] 新 key 存根域（兼容迁移旧 `last_api_domain` 全 URL）
- [x] 命中劣质域则清除并重新发现
- [x] 有合法根域时先可用再后台刷新；无缓存则阻塞发现
- [x] `_signedHeaders` 使用 version `504`
- [x] 移除/不再竞速写死的 ipixiv、release 固定列表（保底由发现模块提供 japi）
- [x] `dart analyze` 无 error

## 笔记

缓存粒度 = 根域；每次启动/刷新对非常规 japi 重新随机子域拼 `_baseUrl`。
发现成功后写入 `api_domains` 列表供下次种子。
