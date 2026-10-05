## 2026-10-05 — 受限档进播放页卸封面并收紧海报视口
- PRD / Tickets：PRD-20261005-02 / specs/tickets/playback-cover-unload/01-unload-and-viewport.md
- 摘要：低内存设备进播放页时，仍挂在树上的浏览封面先松开图片流，下一帧再 `ImageCache.clear()`。海报列表 `scrollCacheExtent` 为 0 像素，首页不再预建相邻分类。
- 验证：`flutter test test/playback_cover_gate_test.dart test/device_profile_test.dart` 19 项通过。`flutter analyze` 无 error（既有 info/warning 未动）。未做真机播放冒烟。
- 规范飞轮：已写回 `.cursor/rules/player-discipline.mdc` 内存档两条（闸门卸载、视口与单分类）
