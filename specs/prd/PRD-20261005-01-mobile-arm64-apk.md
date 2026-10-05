# 手机包只保留 arm64
- 编号：PRD-20261005-01 ｜ 确认人：用户（解决体积增大） ｜ 档位：小修×碰 Android 打包 ｜ 栈位：非代码（Gradle / CI）

## 要解决什么问题（1 段）

v1.0.9 为让电视 `--split-per-abi` 能编过，删掉了手机 flavor 的 `ndk.abiFilters`。`--target-platform android-arm64` 只决定 `libflutter.so` / `libapp.so`，滤不掉 `media_kit` AAR 里的 `libmpv.so`。未 split 的手机包因此同时打进 `arm64-v8a`、`armeabi-v7a`、`x86_64`，体积从约 35MB 增到 61.8MB，文件名仍写成 arm64。电视 64 位包仍是约 35MB。

## 用户故事与验收标准
作为侧载手机包的用户，我想要手机 APK 只含 arm64 原生库，以便体积回到约 35MB，且不会在多 ABI 包里抽到 v7a 兼容库。
- [ ] 手机 release APK 的 `lib/` 只有 `arm64-v8a`，不含 `armeabi-v7a`、`x86`、`x86_64`
- [ ] 电视 `--split-per-abi` 仍能同时产出 `armeabi-v7a` 与 `arm64-v8a` 两个 APK
- [ ] Gradle 中没有 `ndk.abiFilters`

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 手机包 | release、flavor mobile、`CINE_SURFACE=mobile`、`android-arm64` | 解包看 `lib/` | 只有 `lib/arm64-v8a/*.so`，含 `libflutter.so` 与 `libmpv.so` |
| 电视包 | release、flavor tv、`android-arm,android-arm64`、`--split-per-abi` | 解包两个 APK | v7a 包只有 `lib/armeabi-v7a`，arm64 包只有 `lib/arm64-v8a` |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | 如何丢掉多余 ABI | 手机 variant 的 `packaging.jniLibs.excludes`，并在手机构建加上 `--split-per-abi` | `abiFilters` 与工程级 splits 冲突，v1.0.8 已因此失败；电视 split 包已证明 split 会按 ABI 剔除 AAR 里的其他 `.so` | 2026-10-05 |
| 2 | 是否恢复全局 abiFilters | 不恢复 | 红线禁止；任一 flavor 上的 abiFilters 都会让电视 splits 配置失败 | 2026-10-05 |

## 实现约束
- 引用：`.cursor/rules/android-tv-packaging.mdc`
- 须装载技能：cine-flutter-dev

## 不做的事
- 不改 release 签名（debug 证书、缺 v1 签名文件）
- 不改电视 32 位产物
- 不升级版本号、不打 tag
