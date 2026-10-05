# 手机包只保留 arm64
- 日期：2026-10-05
- PRD：PRD-20261005-01
- Tickets：`specs/tickets/mobile-arm64-apk/01`

## 变更摘要
- 手机 variant 用 `packaging.jniLibs.excludes` 丢掉 `armeabi` / `armeabi-v7a` / `x86` / `x86_64` / `mips` 的插件 `.so`
- 手机构建命令加上 `--split-per-abi`（仍只传 `android-arm64`）
- 不写 `ndk.abiFilters`，电视 split 继续同时产出 32 位与 64 位

## 验证
- [x] 带 `--split-per-abi` 的手机包 34.9 MiB，`lib/` 只有 `arm64-v8a`（含 `libflutter.so`、`libmpv.so`）
- [x] 不带 `--split-per-abi` 的手机包同样 34.9 MiB，只有 `arm64-v8a`（excludes 单独生效）
- [x] 电视 `armeabi-v7a` 31.9 MiB、`arm64-v8a` 34.9 MiB，各自只有对应 ABI
- [x] `flutter analyze` 无 error（既有 info/warning 仍在）
