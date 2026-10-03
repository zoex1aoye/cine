# 01 桌面端与 Linux 播放性能及内存优化
- 状态： [x] 完成
- PRD：PRD-20261003-04
- 依赖：无
- 栈位：player / 全栈
- 须装载：cine-flutter-dev

## 交付什么
优化 Linux 及桌面端播放内核的内存与 CPU 开销：
1. 桌面端 MPV demuxer 缓冲区调整为 48MB/24MB（预读 25s/缓存 40s），启用 `vd-lavc-fast: yes` 加速软解；
2. 播放开始后彻底剔除视频槽后方 `_buildBlurredPosterBase` 里的 BackdropFilter 高斯模糊层，并移除非播放态前景毛玻璃；
3. 进播放页时桌面端主动执行 PaintingBinding imageCache.clear()，释放首页旧海报。

## 验收
- [x] 桌面端初始化时 demuxer 前向缓冲从 128MB 降至 48MB，后向缓冲从 64MB 降至 24MB
- [x] 视频起播后，底层 BackdropFilter 彻底被 const ColoredBox 替换
- [x] 进播放页时主动执行 PaintingBinding imageCache.clear()，释放首页旧海报
- [x] `flutter analyze` 零 error
- [x] 播放、切线、拖动进度条功能正常

## 笔记
守住 player-discipline：`*_native.dart` 与 `*_stub.dart` 接口保持一致。
