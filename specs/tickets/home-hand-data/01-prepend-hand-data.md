# 01 首页 hand_data 前置
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261002-02
- 依赖：无
- 栈位：api
- 须装载：cine-flutter-dev

## 交付什么

- `JpApi.getHomeHandData` → `GET /dyTag/hand_data?category_id=`
- `MubuApiClient` + `JpApiClientImpl` 暴露并映射
- 合并工具：page=1 前置去重截断
- 首页分类加载与「查看全部」第 1 页使用合并

## 验收

- [x] 有 `getHomeHandData` 且失败吞掉为空 map
- [x] 首页 tag 第 1 页前置 hand_data
- [x] TagVideosPage 带 categoryId 时第 1 页同样前置
- [x] `flutter analyze` 相关文件无 error
