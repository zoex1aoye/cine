# 02 1GB Device Profile & Image Cache Budget
- 状态： [x] 完成
- PRD：PRD-20261003-02
- 依赖：01
- 栈位：UI / 全栈
- 须装载：cine-flutter-dev

## 交付什么
1. `lib/utils/device_budget.dart`：`DeviceProfileTier { normal, constrained, ultra }` 与各档 `DeviceBudget`（native / stub 共用）；`tierFor(totalMem, lowRam)` 推导档位；
2. `device_profile_native.dart` / `device_profile_stub.dart`：暴露 `tier` / `isConstrained` / `isUltra` / `budget`；`MainActivity` 的 `getMemoryInfo` 增加 `lowRam`；
3. `MovieCard`：封面只传 `memCacheWidth`，宽度由 `budget.coverDecodeWidth` 给出，只看内存档；
4. `PlayerPage` 进入时 `trimImageCacheOnPlayerEnter()`：仅受限档 `ImageCache.clear()`。

## 验收
- [x] `tierFor` 单测覆盖 ultra / constrained / normal / low-ram 边界
- [x] 预算随档位单调递减；ultra 后向缓冲 >= 4MB
- [x] `trimImageCacheOnPlayerEnter`：受限档驱逐空闲项且 live 图片保持追踪；常规档不动
- [x] `flutter analyze` 无 error
