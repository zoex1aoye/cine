# 05 TV Decode Mode UI & Software Loopfilter
- 状态： [x] 完成
- PRD：PRD-20261003-03
- 依赖：04
- 栈位：UI / player
- 须装载：cine-flutter-dev

## 交付什么
1. `media_kit_player_native.dart`：受限档且软解时 `vd-lavc-skiploopfilter=nonkey`（含设备无硬解的初始路径），硬解恢复 `default`；`toggleDecodeMode()` 保留进度并持久化用户偏好；
2. `lib/player/tv_player_keys.dart`：TV 播放页按键策略，焦点在控件栏内时放行方向/确认键；
3. `cine_video_controls.dart`：解码徽标仅 `supportsDecodeToggle` 时显示；隐藏时控件 `ExcludeFocus`；TV 上 Slider 不参与焦点。

## 验收
- [x] 软解降载参数下发（含初始软解路径）
- [x] 焦点在控件栏时 →/OK 到达并激活徽标（见 `test/tv_player_keys_test.dart`）
- [x] 非 Android 不显示徽标
- [ ] TV 实机用遥控器走通 `↑` 进控件栏 → 切换 → 返回（需实机）
- [x] `flutter analyze` 无 error
