# TV 1GB 内存侧载优化与性能增强
- 日期：2026-10-03
- PRD：PRD-20261003-02
- Tickets：`specs/tickets/tv-1gb-sideload-perf/01`–`05`

## 变更摘要
- TV Manifest 侧载桌面兼容：新增普通 `LAUNCHER` category 支持非 Android TV / AOSP 第三方桌面图标展示；增加 `android:banner` 电视横幅与 `largeHeap="true"` 权限提升进程堆上限。
- Gradle 动态 ABI 过滤：支持 `-Ptarget-platform=android-arm` 打出 `armeabi-v7a` 安装包，适配 32位固件的 1GB 低端电视/投影仪。
- DeviceProfile 1GB 极限内存调优：
  - `PaintingBinding.imageCache` 上限收敛至 30 张 / 24MB；
  - TV / 受限模式下 `MovieCard` 封面 decode 宽限制在 180px，防止大屏高 DPR 撑爆显存；
  - 进播放页时主动执行 `DeviceProfile.trimImageCacheOnPlayerEnter()` 回收闲置图片显存。
- Native 播放内核调优与解码健壮性：
  - 受限档启用 `demuxer-donate-buffer=yes`，分片播放后主动向系统归还物理 RAM；
  - 前向缓冲收缩至 8MB、后向收缩至 2MB，减少流媒体网络包内存常驻；
  - 扩充底层显式硬解异常捕获词库（包含 dequeue buffer、surface abandoned、omx/c2/amediaerror 等 SoC 驱动死锁特征）；
  - 增加 5 秒硬解静默假死看门狗（Watchdog），遇到流已加载但第 0 秒进度不走时自动触发软解回退（`hwdec=no`）；
  - 软解降载优化：低端机软解时启用 `vd-lavc-skiploopfilter=nonkey` 跳过非关键帧滤波，保音画同步；CMA 显存 `hwdec-extra-frames` 调优至 1；
  - TV 遥控器交互：播放全屏控制栏增加遥控器可聚焦的「硬解/软解」状态切换按钮，支持用户手动救砖。

## 验证
- [x] `flutter analyze` 无 error
- [x] `flutter test` 全部 78 个测试通过
