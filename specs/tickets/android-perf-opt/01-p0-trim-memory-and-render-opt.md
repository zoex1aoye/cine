# 01 [P0] Android onTrimMemory 联动、后台暂停与播放页离屏模糊消除
- 状态： [x] 完成
- PRD：PRD-20261003-05
- 依赖：无
- 栈位：全栈 / player + ui
- 须装载：cine-flutter-dev

## 交付什么
1. 在 `MainActivity.kt` 注册 `ComponentCallbacks2`，捕获 `onTrimMemory` 并经 `MethodChannel('com.example.cine/device')` 发送 `onTrimMemory` 事件，Dart 侧在 `DeviceProfile` 中注册监听并在内存告急或切后台时执行 `PaintingBinding.instance.imageCache.clear()`；
2. 在 `PlayerPage` 完善 `didChangeAppLifecycleState` 监听，切后台（`paused`/`hidden`）时若在播放则主动挂起播放器，返回前台（`resumed`）时按需恢复；
3. 将 `PlayerPage` 内残余的背景 `BackdropFilter` 以及错误蒙层在 Android / 移动端与受限设备下替换为静态无离屏通道的半透明/纯色层。

## 验收
- [x] Native 到 Dart 的 `onTrimMemory` 链路打通并安全无崩溃
- [x] 切后台播放器正确暂停，回前台恢复
- [x] 播放页在 Android 下无 `BackdropFilter` 激活
- [x] `flutter analyze` 零 error
- [x] `flutter test` 全部通过

## 笔记
守住单向降级与测试用例隔离，确保在非 Android 平台与单元测试中不抛 MissingPluginException。
