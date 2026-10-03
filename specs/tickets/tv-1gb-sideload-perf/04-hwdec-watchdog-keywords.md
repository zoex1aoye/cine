# 04 Hwdec Failure Keywords & Silent Freeze Watchdog
- 状态： [x] 完成
- PRD：PRD-20261003-03
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么
1. `lib/player/hwdec_policy.dart`：`looksLikeHwdecFailure` 失败特征（不含泛化的 `mediacodec` + `error`）；`ensureProbed` 并发安全；
2. `lib/player/hwdec_watchdog.dart`：纯 Dart 看门狗，仅在「硬解生效 + 有视频轨 + 播放中 + 未缓冲」累计 5 秒，到点用 `estimated-vf-fps` 实测；探测不可用不回退；
3. `media_kit_player_native.dart`：回退额度按实例、按源；回退保留进度与暂停态。

## 验收
- [x] 缓冲 / 暂停 / 纯音频 / 软解 / 探测不可用 均不触发（见 `test/hwdec_watchdog_test.dart`）
- [x] 无帧输出 5 秒精准触发一次
- [ ] 目标 SoC 上 `estimated-vf-fps` 行为实机确认（需实机）
- [x] `flutter analyze` 无 error
