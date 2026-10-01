# Cursor Cloud Linux VM 环境笔记

本文件记录在 Cursor Cloud 无头 Linux VM 上跑幕布时的非显而易见细节。本地 macOS/Windows 开发可忽略。

## Environment

- Flutter SDK (stable) 在 `/opt/flutter`，经 `~/.bashrc` 进 PATH；启动时会自动 `flutter pub get`
- 桌面 GUI：`DISPLAY=:1`（图形会话已设；裸 shell 需自行 export）

## Run (Linux desktop, dev)

- `flutter run -d linux`，或 `flutter build linux --debug` 后跑 `build/linux/x64/debug/bundle/cine`（设 `DISPLAY=:1`）
- 无害噪音：`libEGL ... DRI3`（软渲染回退）、ALSA / `Failed to create AudioController`（无声卡）、`Failed to load window icon`、`screen_brightness` 的 `MissingPluginException`（亮度手势仅移动端）。均不挡 UI/播放
- `main()` → `Hive.initFlutter()` → `getApplicationDocumentsDirectory()`。Linux 依赖 `xdg-user-dirs` 与 `~/.config/user-dirs.dirs` 中的 `XDG_DOCUMENTS_DIR`。缺则抛 `MissingPlatformDirectoryException`，应用到不了 `runApp`。修复：`xdg-user-dirs-update` / 重建该文件
- seek-preview 缩略图仅在播放器**内部全屏**（`VideoState.isFullscreen()`）渲染

## Lint / Test

- `flutter analyze`：可通过，约有 ~196 条既有 info/warning（非 setup 引入）
- `flutter test`：`test/widget_test.dart` 当前失败——直接 pump `MubuApp` 未初始化 `late MubuApiClient.instance`，触发 `LateInitializationError`（代码/测试缺陷，非环境问题）

## System deps（快照已装）

Build：`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev mpv` 与 `libstdc++-14-dev`（clang 链 GCC 14 的 libstdc++）。CMake 报过期 `/usr/local` install-prefix 时先 `flutter clean`。
Run：`xdg-user-dirs`（见上）。
