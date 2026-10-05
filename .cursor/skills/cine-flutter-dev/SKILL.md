---
name: cine-flutter-dev
description: >-
  幕布 (Cine) Flutter 开发手册：目录落位、API 初始化、Hive、测速选线、播放器、
  Android TV 打包与遥控、低端内存档。改 lib/、android/ 或 release workflow 前使用。
---

# Cine Flutter Dev

## 技术栈

- Flutter SDK ^3.7；Material 深色主题（`MubuApp` 色常量）
- 播放：`media_kit` + libmpv；Web 走 stub
- 本地：Hive（bookmarks / history / config / node_speeds / source_probes）
- 网络：`http` + 自定义签名（`JpApi`）；启动域名测速

## 开工检查

1. 读 `AGENTS.md` 红线与路由
2. `flutter pub get`（若依赖变更）
3. 目标设备：`flutter devices`；桌面需对应平台工具链

## 常见任务落位

| 任务 | 落点 |
|------|------|
| 新 API | `lib/api/` + 必要时 `models/` |
| 新页面 | `lib/pages/` + 从 `home_page` 等导航挂上 |
| 播放控件/硬解/TV 遥控/内存档 | `lib/player/` + `player-discipline` |
| Android flavor / ABI / TV 清单 | `android/` + `android-tv-packaging` |
| 卡片/弹窗/骨架 | `lib/widgets/` |
| 测速/选源 | `lib/utils/source_*.dart`、`stream_probe.dart` |

## API 与启动

- `MubuApiClient.instance = JpApiClientImpl()` 在 `main()`；UI/测试依赖此前完成
- `JpApi.init()`：缓存优先 + 超时；失败由首页重试——勿改成阻塞启动的死等
- 改签名/域名列表：只改 `jp_api.dart` 一处真相源，并考虑旧 Hive config 缓存

## 播放器

- 内部全屏 vs 窗口全屏；seek-preview 仅内部全屏
- TV：未内部全屏方向键走焦点；seek/音量只在内部全屏。细则 `player-discipline`
- 改 `*_native.dart` 必改 stub
- 验证：唤出控件、Seek、音量、切线、进出内部全屏、至少一条流

## Android TV 打包

细则 `.cursor/rules/android-tv-packaging.mdc`。禁止在 Gradle 写 `ndk.abiFilters`。

```bash
flutter build apk --release --flavor mobile \
  --dart-define=CINE_SURFACE=mobile --target-platform android-arm64 \
  --split-per-abi
flutter build apk --release --flavor tv \
  --dart-define=CINE_SURFACE=tv \
  --target-platform android-arm,android-arm64 --split-per-abi
```

手机包必须 `--split-per-abi`。只传 `--target-platform android-arm64` 滤不掉 AAR 里的 `libmpv.so`（v7a / x86_64），包会从约 35MB 涨到约 62MB。Gradle 里手机 variant 另外 exclude 这些 ABI，且仍然禁止 `ndk.abiFilters`。

发版打 tag `v*`（推 `main` 不会出 Release）。打 tag 前 `pubspec.yaml` 的 `+versionCode` 必须大于已有 `v*` tag，workflow 会跑 `scripts/check_android_version_code.sh`，不通过不出 Android 包。核对资产里有 `mubu_*_tv_armeabi-v7a.apk` 和 `mubu_*_tv_arm64-v8a.apk`。

## 验证命令

```bash
flutter analyze
flutter test
flutter run -d macos   # 或 linux / windows / 设备 id
```

已知：`test/widget_test.dart` 未初始化 API client 会 LateInit——新测试不要复制该写法。

## 提交前

- analyze 无 error
- 票面验收勾完
- 用户指令才 commit（见 git-conventions）
