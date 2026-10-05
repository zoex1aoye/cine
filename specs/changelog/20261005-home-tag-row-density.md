## 2026-10-05 — 非电视首页 tag 行密度
- PRD / Tickets：PRD-20261005-01 / specs/tickets/home-tag-row-density/01-non-tv-row-density.md
- 摘要：非电视列数上限放宽为 3/5/6/8/12，首页 tag 一行按列数请求并在变宽时补拉；电视列数与 12 条请求不变。请求条数由父级传入，tag 行不在 initState 里读 MediaQuery。
- 验证：`flutter analyze` 无 error；`flutter test test/home_tag_row_density_test.dart test/low_end_pad_tv_perf_test.dart` 通过。未做桌面窗口拉宽冒烟。
- 同日：大屏详情弹层不再沿用 Material 3 的 640 宽上限，宽度跟着卡片放大，避免右栏按钮溢出。
- 规范飞轮：无
