## 2026-10-06 — 中心播停随播放器缩放，搜索结果铺满窗口
- PRD / Tickets：PRD-20261006-01 / specs/tickets/center-play-search-fill/01
- 摘要：中心播停圆键和全屏 ±10 秒按播放器短边缩放。「查看全部」和搜索都按可滚距离是否达到半个视口来决定还要不要翻页；搜索每页固定 10 条，查看全部仍是 30 条且返回不足即停。
- 验证：`flutter analyze` 无 error；`flutter test test/center_play_button_test.dart test/search_viewport_fill_test.dart` 通过。未做播放器实机冒烟。
- 规范飞轮：未写回。查询条数上限已在标签页与搜索补页两处出现，待确认是否写入规则。
