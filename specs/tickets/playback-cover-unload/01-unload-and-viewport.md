# 01 受限档卸封面并收紧海报视口
- 状态： [x] 完成
- PRD：PRD-20261005-02
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么
低内存设备进入播放页后，仍挂在树上的浏览封面松开图片流；海报列表不再预建视口外的行，首页不再预建相邻分类。

## 验收
- [x] `PlaybackCoverGate` 深度计数；播放页受限档 acquire / dispose release
- [x] `FailoverCoverImage` 在受限档且闸门拉起时改为纯色占位；`holdDuringPlayback` 除外
- [x] 首页 / 收藏 / 历史 / 筛选 / 搜索 / 标签页的海报 `CustomScrollView` 使用 `scrollCacheExtent: DeviceProfile.posterCacheExtent`
- [x] 受限档首页用当前分类单页，不用 `TabBarView`
- [x] `flutter test test/playback_cover_gate_test.dart test/device_profile_test.dart` 通过
- [x] `flutter analyze` 无 error

## 笔记
- 清缓存仍只用 `ImageCache.clear()`，且放在 acquire 之后的下一帧
