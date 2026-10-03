# 02 1GB Device Profile & Image Cache Budget
- 状态： [x] 完成
- PRD：PRD-20261003-02
- 依赖：01
- 栈位：UI / 全栈
- 须装载：cine-flutter-dev

## 交付什么
1. `lib/utils/device_profile_native.dart` 与 `device_profile_stub.dart`：
   - 细化对 1GB 设备（`totalMem <= 1.2GB` 或 `isTvSurface && isConstrained`）的内存预算；
   - 1GB 内存下 `constrainedImageCacheCount = 30`，`constrainedImageCacheBytes = 24 << 20` (24MB)；
   - 封面解码上限 `constrainedCoverMemWidth = 180`；
2. `MovieCard` 与 `FailoverCoverImage`：
   - TV 模式下对 memCacheWidth 封顶 180px，防止大屏高 DPR 解码产生超大 Bitmap；
3. 播放页 `PlayerPage` 进入与离开时触发 `DeviceProfile.trimImageCacheOnPlayerEnter()`，主动释放未引用图片，为播放器留出内存空间。

## 验收
- [ ] 1GB 内存设备上 `PaintingBinding.instance.imageCache` 上限为 30 张 / 24MB
- [ ] 播放页初始化触发内存修剪
- [ ] 单测用例验证通过
- [ ] `flutter analyze` 无 error
