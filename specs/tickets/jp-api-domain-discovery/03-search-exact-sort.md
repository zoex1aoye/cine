# 03 search 精确标题优先排序
- 状态： [x] 完成
- PRD：PRD-20261001-01
- 依赖：02
- 栈位：api
- 须装载：cine-flutter-dev

## 交付什么

`JpApi.search` 在解析 `/v2/search/videoV2` 列表后，按精确 title → title/original_name 包含 → 其余做稳定排序。

## 验收

- [x] 精确匹配条目排在包含匹配之前
- [x] 仍只请求 videoV2；无别名二次搜索
- [x] `dart analyze` 无 error

## 笔记

在转为 `VideoItem` 前对 raw map 排序，以便使用 `original_name`。
