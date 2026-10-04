# TV 32/64 位包与遥控焦点
- 日期：2026-10-04
- PRD：PRD-20261002-05
- Tickets：`specs/tickets/android-mobile-tv-surface/06-tv-abi-and-remote.md`

## 变更摘要
- TV flavor 同时允许 `armeabi-v7a` 与 `arm64-v8a`；workflow 分 ABI 产出。mobile 仍仅 arm64
- 分类筛选：分类芯片、已选条件、筛选弹层可被遥控器聚焦；非当前 Tab 排除焦点
- 播放详情：未内部全屏时方向键走返回 / 收藏 / 播放 / 全屏 / 线路 / 剧集；内部全屏才启用 seek 与音量

## 验证
- [x] `flutter test test/tv_remote_focus_test.dart`
- [x] `flutter analyze` 无 error
