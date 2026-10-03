# Linux 桌面端播放性能与内存优化
- 日期：2026-10-03
- PRD：PRD-20261003-04
- Tickets：`specs/tickets/linux-perf-opt/01-desktop-demuxer-and-render-opt.md`

## 变更摘要
- 播放内核 demuxer 缓冲区优化 (`lib/player/media_kit_player_native.dart`)：
  - 桌面端前向缓冲由 128MB 收敛至 48MB (`50331648`)，后向缓冲由 64MB 收敛至 24MB (`25165824`)，预读 25s / 缓存 40s，流缓冲 2MB。在保证 1080P/4K HLS 秒开与拖拽缓存的前提下，缩减物理常驻内存 100MB+。
  - 新增 `demuxer-donate-buffer: yes`：解码帧渲染消费后内核立即释放 packet buffer 堆内存。
  - 新增 `vd-lavc-fast: yes`：软解快速模式，优化非关键去块滤波，视觉无损且显著降低 CPU 负载。
- 渲染通道离屏开销消除 (`lib/pages/player_page.dart`)：
  - 视频槽底层底图：起播/显示视频后，底图 `_buildBlurredPosterBase` 切换为静态 `const ColoredBox(color: Color(0xFF070708))`，彻底消除播放期间的离屏高斯模糊通道（Offscreen Buffer）。
  - 起播前景蒙层：将原 `BackdropFilter` 全屏动态高斯模糊替换为静态遮罩 `const ColoredBox(color: Color(0x73070708))`，杜绝首帧前后的模糊合成开销。
  - 顶栏线路切换快捷入口：桌面端在顶栏增加线路切换胶囊按钮，并适配居中弹窗展示。
- 内存缓存主动治理 (`lib/pages/player_page.dart`)：
  - 桌面端进入播放页时主动执行 `PaintingBinding.instance.imageCache.clear()`，清除非引用首页海报图片缓存，为视频解码释放物理内存空间。
- 代码洁癖与维护性修复：
  - 清理 `lib/pages/player_page.dart` 中未使用的私有成员与冗余导入。

## 验证
- [x] `flutter analyze lib/pages/player_page.dart lib/player/media_kit_player_native.dart`：0 error, 0 warning
- [x] `flutter test`：全量 106 项自动化测试全部通过
- [x] 实机/虚拟机验证：在 Linux X11 环境构建并启动运行 `build/linux/x64/debug/bundle/cine`，进播放页后物理常驻内存（RSS）由 930MB+ 降至约 690MB，内存降幅超 240MB，CPU 占用稳定。
- 规范飞轮：无
