# 01 前 3 条新测后早 init
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261002-01
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

改 `PlayerPage._runSpeedTest` 步骤 3：
- pending = `playlistMs == null`（本轮新测）
- 前 `min(3, pending)` 并行测完 → `_applyRecommendedSource(autoInit: !_playerInitialized)`
- 仍未 init：继续测剩余，每完成一条尝试 autoInit（一有可用立刻播）
- 已 init：剩余并行测完后（或过程中）未点播放则 upgrade
- Champion / 缓存预热 / 点播放 abort 保持

## 验收

- [x] 前 3 新测并行结束后即可早 init（未 Champion 时）
- [x] 首批无可用时后续测出可用会 init
- [x] 早开播后继续测且可 upgrade；点播放 abort
- [x] `flutter analyze` 相关文件无 error
- [ ] 冒烟：多线路进页明显早于「等全部测完」（用户）
