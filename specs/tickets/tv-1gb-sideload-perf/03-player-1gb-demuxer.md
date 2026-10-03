# 03 Native Player 1GB Demuxer & Buffer Tuning
- 状态： [x] 完成
- PRD：PRD-20261003-02
- 依赖：02
- 栈位：播放器 / Player
- 须装载：cine-flutter-dev

## 交付什么
1. `lib/player/media_kit_player_native.dart`：
   - 在受限档（constrained）下配置 `demuxer-donate-buffer=yes`（使 mpv 及时归还已释放分片的物理内存）；
   - 受限档缓冲区优化：前向缓冲收缩至 8MB，后向缓冲收缩至 2MB，读前缓冲 `readahead-secs=8`，`cache-secs=15`；
   - 避免网络流过大 I/O 挤占系统 RAM。
2. 配合 `HwdecPolicy`，保障 MediaCodec 硬解正常走 Surface 渲染。

## 验收
- [ ] 受限档 mpv 属性配置包含 `demuxer-donate-buffer=yes`
- [ ] 单测与冒烟验证通过
- [ ] `flutter analyze` 无 error
