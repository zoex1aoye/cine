# 01 Expand Error Keywords & Silent Freeze Watchdog
- 状态： [x] 完成
- PRD：PRD-20261003-03
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么
在 `lib/player/media_kit_player_native.dart`：
1. 扩充 `_looksLikeHwdecFailure` 匹配关键词：
   - 增加 `dequeue output buffer`、`error while decoding`、`omx error`、`c2 error`、`amediaerror`、`surface abandoned`、`surface invalid`、`mediacodec` 相关的常见驱动死锁特征；
2. 实现 `_startHwdecWatchdog()`：
   - 视频处于加载/开播状态，若 5 秒内 `duration > Duration.zero` 或正在缓冲，但 `position == Duration.zero` 且未成功播放，自动判定为硬解管线假死；
   - 自动触发 `_fallbackToSoftwareDecode()` 一键切软解并取消看门狗。

## 验收
- [ ] 显式错误匹配覆盖常见联发科/晶晨驱动异常
- [ ] 假死看门狗在正常播放时不误触，5s 假死时精准触发一次软解 reopen
- [ ] `flutter analyze` 无 error
