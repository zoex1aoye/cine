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

## 验证
- [x] `flutter test`：`device_profile` / `hwdec_policy` / `hwdec_watchdog` / `tv_remote_focus` 通过
- [ ] 1GB 电视实机冒烟未做
