# Android mobile/tv 双线 + 低端自适应
- 日期：2026-10-02
- PRD：PRD-20261002-05
- Tickets：`specs/tickets/android-mobile-tv-surface/01`–`05`

## 变更摘要
- Android `productFlavors`：`mobile` / `tv`；tv `applicationIdSuffix=.tv`，Leanback 入口且 `required=false`
- Dart `CINE_SURFACE` + `DeviceProfile`（&lt;2GB → constrained 缓冲/图片/KeepAlive）
- Android MediaCodec 硬解探测 + 失败最多 reopen 软解一次
- TV：浏览焦点（导航轨 / MovieCard）与播放遥控键位
- **Fire HD 8 实机**：默认 Impeller 启动 SIGSEGV → Manifest 关闭 Impeller（Skia）

## 验证
- [x] `flutter build apk --flavor mobile --dart-define=CINE_SURFACE=mobile --debug …` → `app-mobile-debug.apk`
- [x] `flutter build apk --flavor tv --dart-define=CINE_SURFACE=tv --debug …` → `app-tv-debug.apk`
- [x] `flutter analyze` 无 error（既有 warning/info 仍在）
- [x] Fire HD 8（1.4GB）：`--no-enable-impeller` 后首页+播片可用；随后 Manifest 固化 `EnableImpeller=false`
