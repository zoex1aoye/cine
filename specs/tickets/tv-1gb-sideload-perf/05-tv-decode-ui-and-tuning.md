# 02 TV Decode Mode UI & Software Loopfilter
- 状态： [x] 完成
- PRD：PRD-20261003-03
- 依赖：04
- 栈位：UI / player
- 须装载：cine-flutter-dev

## 交付什么
1. `lib/player/media_kit_player_native.dart`：
   - 受限档及软解下配置 `vd-lavc-skiploopfilter=nonkey`，防止软解 1080P CPU 撑爆导致严重掉帧；
   - 受限档 `hwdec-extra-frames` 设为 `1`，减少 CMA 显存消耗；
   - 暴露 `toggleDecodeMode()` 或 `setHwdecEnabled(bool)` 方法支持手动硬/软解切换。
2. `lib/player/cine_video_controls.dart`：
   - 控制栏在 TV 模式/桌面提供「硬解/软解」状态小徽标按钮；
   - 遥控器可聚焦并一键切换解码模式。

## 验收
- [ ] 软解时下发 skiploopfilter 优化
- [ ] TV 模式控制栏显示解码状态并支持按键切换
- [ ] `flutter analyze` 无 error
