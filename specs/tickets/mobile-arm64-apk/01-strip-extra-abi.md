# 01 手机包去掉多余 ABI
- 状态： [x] 完成
- PRD：PRD-20261005-01
- 依赖：无
- 栈位：非代码（Gradle / CI）
- 须装载：cine-flutter-dev

## 交付什么
手机 release APK 只打包 `arm64-v8a` 原生库；电视 split 仍各含一个 ABI。

## 验收
- [x] 手机包 `lib/` 只有 `arm64-v8a`
- [x] 电视 v7a / arm64 两个包各自只有对应 ABI
- [x] `android/app/build.gradle.kts` 无 `ndk.abiFilters`
- [x] `flutter analyze` 无 error

## 笔记
v1.0.9 手机包多出的体积是 `lib/armeabi-v7a/libmpv.so` 与 `lib/x86_64/libmpv.so`。
