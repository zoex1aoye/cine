# 02 [P1] 瀑布流卡片 RepaintBoundary 隔离与软解降载滤波优化
- 状态： [x] 完成
- PRD：PRD-20261003-05
- 依赖：01
- 栈位：player + ui
- 须装载：cine-flutter-dev

## 交付什么
1. 在 `MovieCard` 与 `MovieSliverGrid` 中为海报卡片添加 `RepaintBoundary`，阻断局部重绘（如焦点放大、阴影变化、动画）向上冒泡污染整个列表视图；
2. 在 `media_kit_player_native.dart` 的软解调优方法 `_applyDecodeTuning` 中，对处于 `DeviceProfile.isConstrained`（受限档/ultra 档）的 Android 设备配置 `vd-lavc-skiploopfilter=nonkey`，减轻低端 A53/A35 芯片软解 CPU 压力。

## 验收
- [x] 瀑布流卡片外层包裹 `RepaintBoundary`
- [x] Android 受限档软解时正确注入 `vd-lavc-skiploopfilter`
- [x] `flutter analyze` 零 error
- [x] `flutter test` 全部通过

## 笔记
不要给极其微小的子组件滥用 `RepaintBoundary`，仅在卡片边界（Card Boundary）设立渲染栅栏。
