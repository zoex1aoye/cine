---
name: cine-flutter-dev
description: >-
  幕布 (Cine) Flutter 开发手册：目录落位、API 初始化、Hive、测速选线、播放器与跨平台验证。
  改 lib/ 下任何代码或跑端调试前使用。
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
| 播放控件/硬解 | `lib/player/`（守 player-discipline） |
| 卡片/弹窗/骨架 | `lib/widgets/` |
| 测速/选源 | `lib/utils/source_*.dart`、`stream_probe.dart` |

## API 与启动

- `MubuApiClient.instance = JpApiClientImpl()` 在 `main()`；UI/测试依赖此前完成
- `JpApi.init()`：缓存优先 + 超时；失败由首页重试——勿改成阻塞启动的死等
- 改签名/域名列表：只改 `jp_api.dart` 一处真相源，并考虑旧 Hive config 缓存

## 播放器

- 内部全屏 vs 窗口全屏；seek-preview 仅内部全屏
- 改 `*_native.dart` 必改 stub
- 验证：唤出控件、Seek、音量、切线、进出内部全屏、至少一条流

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
