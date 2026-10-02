# 01 Android mobile/tv flavors
- 状态： [x] 完成
- PRD：PRD-20261002-05
- 依赖：无
- 栈位：全栈
- 须装载：cine-flutter-dev

## 交付什么
Android 以 `mobile`/`tv` productFlavors 分线打包；Dart `CINE_SURFACE` 可读；tv Manifest 含 Leanback 入口且 required=false。

## 验收
- [x] `productFlavors` dimension `surface`：mobile / tv；tv `applicationIdSuffix=.tv`
- [x] `src/tv/AndroidManifest.xml`：LEANBACK_LAUNCHER；leanback + touchscreen `required=false`
- [x] `lib/utils/cine_surface.dart`：`CineSurface` + `isTvSurface`
- [x] APK 输出名含 surface（如 `mubu_*_tv_arm64.apk`）
- [x] README 或注释写明 `--flavor` + `--dart-define=CINE_SURFACE=…`
- [x] `flutter analyze` 无 error

## 笔记
默认开发可用 `--flavor mobile --dart-define=CINE_SURFACE=mobile`。
