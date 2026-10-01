# 20261001 — 电影线路模式（切换线路 / 测速）

- PRD：`PRD-20261001-04`
- Tickets：`specs/tickets/film-line-mode/01`、`02`
- 日期：2026-10-01

## 变更摘要

电影各 CDN/清晰度线使用互不相同的 `source_name` 时，线路面板与测速不再因「无当前集」整线跳过。代表源改为「当前集优先、否则该线首源」；单源也跑测速；中止探测时写入超时终态，消除永久「检测中…」。电影自动起播**忽略集名、在全部 usable 源中按延迟优先全局选**（剧集仍按当前集对齐）。

## 验证

- [x] `flutter test test/episode_utils_test.dart test/source_picker_test.dart test/detail_source_parse_test.dart`
- [x] `flutter analyze` 相关文件无 error
- [ ] macOS 冒烟：蜡笔小新切换线路 >1 条，结束后非「检测中…」；起播为全局推荐/较快线

## 回滚

恢复 `player_page` 代表源「必须集名匹配」与 `_sources.length > 1` 测速门槛；电影选线重新带上集名 scope。
