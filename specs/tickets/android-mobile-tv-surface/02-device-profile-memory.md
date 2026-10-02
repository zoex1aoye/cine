# 02 DeviceProfile 受限档内存
- 状态： [x] 完成
- PRD：PRD-20261002-05
- 依赖：01
- 栈位：全栈
- 须装载：cine-flutter-dev

## 交付什么
运行时探测低内存进入 constrained：缩小 demux 缓冲、封面解码尺寸与 imageCache，收敛首页 KeepAlive。

## 验收
- [x] `device_profile` native/stub 成对；Android totalMem&lt;2GB → constrained
- [x] `media_kit_player_native` constrained 缓冲：前向约 8–12MB、后向约 4–8MB
- [x] `failover_cover_image` 支持 memCacheWidth/Height；网格传入逻辑宽
- [x] constrained 下调 `imageCache` maximumSize/Bytes；首页 KeepAlive 关闭或减少
- [x] 非 Android / normal 行为与今一致
- [x] `flutter analyze` 无 error

## 笔记
探测经 MethodChannel 读 ActivityManager.MemoryInfo。
