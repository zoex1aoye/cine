# TV 1GB 内存侧载优化与性能增强
- 日期：2026-10-03
- PRD：PRD-20261003-02
- Tickets：`specs/tickets/tv-1gb-sideload-perf/01`–`03`

## 变更摘要
- TV Manifest 侧载桌面兼容：新增普通 `LAUNCHER` category 支持非 Android TV / AOSP 第三方桌面图标展示；增加 `android:banner` 电视横幅与 `largeHeap="true"` 权限提升进程堆上限。
- Gradle 动态 ABI 过滤：支持 `-Ptarget-platform=android-arm` 打出 `armeabi-v7a` 安装包，适配 32位固件的 1GB 低端电视/投影仪。
- DeviceProfile 1GB 极限内存调优：
  - `PaintingBinding.imageCache` 上限收敛至 30 张 / 24MB；
  - TV / 受限模式下 `MovieCard` 封面 decode 宽限制在 180px，防止大屏高 DPR 撑爆显存；
  - 进播放页时主动执行 `DeviceProfile.trimImageCacheOnPlayerEnter()` 回收闲置图片显存。
- Native 播放内核调优：
  - 受限档启用 `demuxer-donate-buffer=yes`，分片播放后主动向系统归还物理 RAM；
  - 前向缓冲收缩至 8MB、后向收缩至 2MB，减少流媒体网络包内存常驻。

## 验证
- [x] `flutter analyze` 无 error
- [x] `flutter test` 全部 77 个测试通过
