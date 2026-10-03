# 01 TV Sideload Manifest & Build Setup
- 状态： [x] 完成
- PRD：PRD-20261003-02
- 依赖：无
- 栈位：全栈
- 须装载：cine-flutter-dev

## 交付什么
`android/app/src/tv/AndroidManifest.xml`：
1. 保留 Leanback 入口（`LEANBACK_LAUNCHER`，`leanback required=false`）；tv 清单同一 intent-filter 内同时声明 `LEANBACK_LAUNCHER` 与标准 `LAUNCHER`，覆盖 Google/Android TV、第三方 TV 桌面与投影仪魔改 AOSP 桌面；
2. 增加 TV 横幅 `android:banner="@mipmap/ic_launcher"`；
3. `android/app/build.gradle.kts`：`-Ptarget-platform` 映射为 ABI，未知取值忽略，全部无效回落 `arm64-v8a`；
4. 保证 `mobile` 与 `tv` 打包配置完好（CI 同步按 flavor 构建）；
5. CI 对 tv 分别构建 `android-arm64` 与 `android-arm`，产物文件名带真实 ABI（`mubu_<版本>_tv_arm64-v8a.apk` / `mubu_<版本>_tv_armeabi-v7a.apk`），每次构建后立即拷贝（同 flavor 连续构建会清掉上一个 APK）。

## 验收
- [x] tv 包合并后的清单同时含 `LAUNCHER` 与 `LEANBACK_LAUNCHER`（来源见 PRD 决策 #1）
- [x] 不加 `largeHeap` / `hardwareAccelerated`（PRD 决策 #2）
- [x] CI 分别构建 mobile / tv（arm64）与 tv（armeabi-v7a），产物 3 个互不覆盖
- [x] `flutter analyze` 无 error
