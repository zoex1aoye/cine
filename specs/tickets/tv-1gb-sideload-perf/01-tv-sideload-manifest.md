# 01 TV Sideload Manifest & Build Setup
- 状态： [x] 完成
- PRD：PRD-20261003-02
- 依赖：无
- 栈位：全栈
- 须装载：cine-flutter-dev

## 交付什么
优化 `src/tv/AndroidManifest.xml`：
1. 兼顾 Leanback Launcher 与标准 Launcher（确保非 Google TV / 普通 AOSP 投影仪桌面也能显示 App 图标）；
2. 增加 TV 横幅声明 `android:banner="@mipmap/ic_launcher"`；
3. 声明 `android:largeHeap="true"` 与 `android:hardwareAccelerated="true"`。
4. 保证 `mobile` 与 `tv` 打包配置完好，支持常见架构侧载。

## 验收
- [ ] `src/tv/AndroidManifest.xml` 支持双 category 启动或多 intent-filter
- [ ] 开启 `largeHeap`
- [ ] `flutter analyze` 无 error
