# 拣入低端设备与 TV 内存/硬解优化
- 日期：2026-10-04
- 来源：`cursor/tv-1gb-sideload-perf-268e`、`cursor/android-perf-opt-p0-p2-b080`（拣选，非整支合并）

## 变更摘要
- 内存三档：`ultra`（≤1.2GiB 或系统 low-ram）、`constrained`（<2GiB）、`normal`。预算在 `DeviceBudget`。
- 封面只限制解码宽度；进播放页时受限档 `ImageCache.clear()`。
- Android `onTrimMemory` / `onLowMemory` 清闲置封面；切后台暂停解码，回前台恢复。
- Android 与受限档的播放页遮罩不再用实时 `BackdropFilter`。
- 硬解假死看门狗按出帧判断，失败保留进度并在换集时重试硬解；软解按档位跳过环路滤波。
- TV 清单同时声明 `LEANBACK_LAUNCHER` 与 `LAUNCHER`。
- 未接入对方的播放遥控键位和 ABI 打包（当前分支已有另一套）。

## 审查修复
- 软解回退和换集的 `open` 走同一条队列，旧任务在换源后跳过
- 看门狗不再把视频宽度当成已经出帧
- 切后台只在 `hidden` / `paused` 暂停，通知栏一类的 `inactive` 不停
- TV 清单不再重复声明 `LAUNCHER`；Leanback 横幅改为 16:9
- 遥控焦点只画红框，不再缩放，避免密排芯片叠在一起

## 验证
- [x] `flutter test`：`device_profile` / `hwdec_policy` / `hwdec_watchdog` / `tv_remote_focus` 通过
- [ ] 1GB 电视实机冒烟未做
