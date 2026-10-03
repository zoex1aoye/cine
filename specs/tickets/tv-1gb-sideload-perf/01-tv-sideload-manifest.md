# 01 TV Sideload Manifest & Build Setup
- 状态： [x] 完成
- PRD：PRD-20261003-02
- 依赖：无
- 栈位：全栈
- 须装载：cine-flutter-dev

## 交付什么
`android/app/src/tv/AndroidManifest.xml`：
1. 保留 Leanback 入口（`LEANBACK_LAUNCHER`，`leanback required=false`）；普通 `LAUNCHER` 由 `main` 清单提供，flavor 合并后并存，不重复声明；
2. 增加 TV 横幅 `android:banner="@mipmap/ic_launcher"`；
3. `android/app/build.gradle.kts`：`-Ptarget-platform` 映射为 ABI，未知取值忽略，全部无效回落 `arm64-v8a`；
4. 保证 `mobile` 与 `tv` 打包配置完好（CI 同步按 flavor 构建）。

## 验收
- [x] tv 包合并后的清单同时含 `LAUNCHER` 与 `LEANBACK_LAUNCHER`（来源见 PRD 决策 #1）
- [x] 不加 `largeHeap` / `hardwareAccelerated`（PRD 决策 #2）
- [x] CI 分别构建 mobile / tv
- [x] `flutter analyze` 无 error
