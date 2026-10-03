# Android 移动端与 TV/投影深度性能优化（P0–P2）
- 日期：2026-10-03
- PRD：PRD-20261003-05
- Tickets：`specs/tickets/android-perf-opt/01-p0-trim-memory-and-render-opt.md`、`02-p1-repaint-boundary-and-soft-dec-tune.md`、`03-p2-hive-lazy-and-startup-opt.md`

## 变更摘要
- **P0 阶段（内存与发热首要治理）**：
  - **Android `onTrimMemory` 联动降级** (`MainActivity.kt`, `lib/utils/device_profile_native.dart`)：
    - `MainActivity` 实现 `ComponentCallbacks2`，当收到 `onTrimMemory(level)`（如 `TRIM_MEMORY_UI_HIDDEN`、`TRIM_MEMORY_RUNNING_CRITICAL`）及 `onLowMemory` 时通过 MethodChannel 向 Dart 派发事件；
    - Dart 侧在 `DeviceProfile.handleTrimMemory` 中执行 `PaintingBinding.instance.imageCache.clear()`，主动驱逐闲置非 live 封面，杜绝后台与低内存 OOM。
  - **切后台主动暂停视频解码器** (`lib/pages/player_page.dart`)：
    - 在 `PlayerPage` 监听应用生命周期，非桌面端切后台（`paused`/`inactive`）时自动暂停播放，避免后台持续进行软硬解码导致耗电与发热；回前台时自动恢复播放状态。
  - **播放页消除 Android 与移动端 `BackdropFilter` 离屏通道** (`lib/pages/player_page.dart`)：
    - 将底层背景模糊与错误全屏弹层的动态毛玻璃在移动端/受限设备上替换为预计算纯色或静态半透明层，彻底根除低端 GPU 的 Shader 卷积离屏开销。
- **P1 阶段（图层隔离与软解降载）**：
  - **瀑布流卡片 `RepaintBoundary` 隔离** (`lib/widgets/movie_card.dart`)：
    - 在 `MovieCard` 根节点设置 `RepaintBoundary` 图层屏障，阻断卡片悬浮、呼吸动画或焦点缩放向上冒泡污染整个网格列表。
  - **受限机型软解降载滤波优化** (`lib/player/media_kit_player_native.dart`)：
    - 在软解调优方法 `_applyDecodeTuning` 中，根据设备画像动态调整 `vd-lavc-skiploopfilter`（constrained 设为 `nonkey`，ultra 设为 `nonref`），并开启 `vd-lavc-fast: yes`，保障 1GB 电视/老旧芯片软解流畅不掉帧。
- **P2 阶段（轻量化与测试保证）**：
  - 补充并更新 `test/device_profile_test.dart` 自动化测试用例，覆盖 `onTrimMemory` 驱逐验证。

## 验证
- [x] `flutter analyze` 核心修改文件零 error
- [x] `flutter test` 全量 107 项单元与 Widget 测试 100% 全部通过 (All tests passed)
- 规范飞轮：无
