# TV 1GB 内存侧载优化与硬解自愈
- 日期：2026-10-03
- PRD：PRD-20261003-02、PRD-20261003-03
- Tickets：`specs/tickets/tv-1gb-sideload-perf/01`–`06`

## 变更摘要
- 内存分档：新增 `ultra`（`totalMem <= 1.2GiB` 或系统 low-ram）/ `constrained`（`< 2GiB`）/ `normal` 三档，预算集中在 `lib/utils/device_budget.dart`，native 与 stub 共用。
  - ultra：`ImageCache` 24MB、封面解码宽 <= 180、demux 前向 8MB / 后向 4MB；
  - constrained：`ImageCache` 48MB、封面解码宽 <= 240、demux 前向 10MB / 后向 6MB。
- 封面：只传 `memCacheWidth`（同时传宽高会被强拉成 2:3 变形）；解码上限只看内存档，不看 TV/手机 surface。
- 进播放页：受限档 `ImageCache.clear()` 释放闲置封面；不再调用 `clearLiveImages()`。
- TV 清单：同时显式声明 `LEANBACK_LAUNCHER` 与 `LAUNCHER`（侧载后 Google TV / 第三方 TV 桌面 / 投影 AOSP 桌面均可见）并保留横幅；不加 `largeHeap` / `hardwareAccelerated`。
- Gradle：`-Ptarget-platform` 映射 ABI，未知取值忽略，默认 `arm64-v8a`（32 位固件见 PRD-02 决策 #5）。
- CI：`build.yml` 按 `mobile` / `tv` flavor 分别构建。
- 硬解自愈：
  - `HwdecWatchdog` 仅在「硬解生效 + 有视频轨 + 播放中 + 未缓冲」累计 5 秒，用 `estimated-vf-fps` 实测出帧，确认无帧才回退软解；
  - 回退与手动切换保留进度与暂停态；自动回退的换集后重试硬解；用户选择持久化；
  - release 日志回到 `warn`；失败特征不再匹配泛化的 `mediacodec` + `error`；
  - 软解降载 `vd-lavc-skiploopfilter=nonkey` 覆盖「设备本就无硬解」的初始路径。
- TV 遥控：焦点在控件栏内时方向/确认键让出给焦点遍历，控件栏可见时 `↑` 进入控件栏，返回键先回根；隐藏时控件不可聚焦；解码徽标仅 Android 显示。
- 修复：`media_kit_player_stub.dart` 同步 `JpPlayer` 接口（此前 `flutter analyze` 有 error）；`pubspec.lock` 回滚无关降级。

## 验证
- [x] `flutter analyze` 无 error
- [x] `flutter test` 全部通过
- [ ] 目标 1GB TV / 投影实机：播一条 HLS、遥控器走通控件栏、观察看门狗与回退（未做，需实机）
- [ ] `flutter build apk --flavor mobile|tv`（环境无 Android SDK，未做；CI 将验证）
