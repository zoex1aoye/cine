# 03 Native Player Demuxer & Buffer Tuning
- 状态： [x] 完成
- PRD：PRD-20261003-02
- 依赖：02
- 栈位：播放器 / Player
- 须装载：cine-flutter-dev

## 交付什么
`lib/player/media_kit_player_native.dart`：受限档（constrained / ultra）按 `DeviceProfile.budget` 下发 `demuxer-max-bytes` / `demuxer-max-back-bytes` / `demuxer-readahead-secs` / `cache-secs` / `stream-buffer-size`。

不做：`demuxer-donate-buffer`（mpv 默认 yes，且语义不是归还内存）、为 MediaCodec 收紧 `hwdec-extra-frames`（对其无效），见 PRD-20261003-02 决策 #3 / #4。

## 验收
- [x] 受限档缓冲参数取自 `DeviceBudget`，不再散落字面量
- [x] 配合 `HwdecPolicy` 保障 MediaCodec 硬解走 Surface 渲染
- [ ] 目标 1GB 设备实机冒烟播一条 HLS（需实机）
- [x] `flutter analyze` 无 error
