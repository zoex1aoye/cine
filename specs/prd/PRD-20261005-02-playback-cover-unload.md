# 受限档进播放页卸封面并收紧海报视口
- 编号：PRD-20261005-02 ｜ 确认人： ｜ 档位：小修×碰播放器·共享组件 ｜ 栈位：player

## 要解决什么问题（1 段）

首页用 `Navigator.push` 盖住下层，分类、收藏、历史仍挂在树上，`ImageCache.clear()` 清不掉仍被封面引用的位图。`TabBarView` 还会预建相邻分类。低内存设备进播放页前，需要先让浏览封面松开图片流，并停止预建视口外的海报行。

## 用户故事与验收标准
作为低内存设备上的用户，我想要进播放页时卸掉被盖住的浏览封面、列表不再预建视口外海报，以便解码留出物理内存。
- [ ] 受限档（`constrained` / `ultra`）进入播放页时 `PlaybackCoverGate.acquire()`，离开时配对 `release()`
- [ ] 浏览封面在闸门拉起且为受限档时不再构建 `CachedNetworkImage`；`holdDuringPlayback: true` 的播放页背景仍解码
- [ ] 常规档不 acquire，封面照常解码；`posterCacheExtent` 为 `null`
- [ ] 受限档海报列表 `scrollCacheExtent` 为 0 像素；首页只建当前分类，顶部分类条仍可切换
- [ ] `flutter analyze` 无 error；闸门与封面卸载测试通过

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 嵌套播放页 | 闸门深度 0 | 两次 acquire，再两次 release | 深度归零后 `isHeld` 为 false；多一次 release 不变成负数 |
| 浏览封面被盖住 | 档位 ultra，闸门已 acquire | 构建 `FailoverCoverImage` | 没有 `CachedNetworkImage`，显示纯色占位 |
| 离开播放页 | 上一场景 | release 并重建一帧 | 重新出现 `CachedNetworkImage` |
| 播放页背景 | 档位 constrained，闸门已 acquire | `holdDuringPlayback: true` | 仍构建 `CachedNetworkImage` |
| 常规档 | 档位 normal，闸门已 acquire | 构建浏览封面 | 仍构建 `CachedNetworkImage`；`posterCacheExtent` 为 null |
| 海报视口 | 档位 ultra 或 constrained | 读 `posterCacheExtent` | `ScrollCacheExtent.pixels(0)` |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | 闸门形态 | 深度计数 | 嵌套播放页不能把标志卡在拉起 | 2026-10-05 |
| 2 | 谁 acquire | 仅 `DeviceProfile.isConstrained` | 常规档内存够，避免无谓闪封面 | 2026-10-05 |
| 3 | 何时 clear | acquire 后的下一帧 | 封面须先丢掉 `ImageStream`，`clear()` 才能放掉位图 | 2026-10-05 |
| 4 | 卸掉时画什么 | `ColoredBox(0xFF1A1A1E)` | 不走转圈占位，避免再挂图片流 | 2026-10-05 |
| 5 | 播放页三张封面 | `holdDuringPlayback: true` | 信箱/加载图仍要显示 | 2026-10-05 |
| 6 | 视口 | 受限档 `ScrollCacheExtent.pixels(0)`，否则 `null` | `null` 保持框架默认；0 像素不预建视口外行。用 `scrollCacheExtent`，不用已弃用的 `cacheExtent` | 2026-10-05 |
| 7 | 首页分页 | 受限档只建当前 `CategoryContentView` | `TabBarView` 会预建相邻页；滑切分类在低内存设备上放弃，分类条保留 | 2026-10-05 |

## 实现约束
- 引用：`.cursor/rules/player-discipline.mdc`、`.cursor/rules/flutter-structure.mdc`
- 须装载技能：cine-flutter-dev
- 禁止 `ImageCache.clearLiveImages()`
- 播放页背景封面必须 `holdDuringPlayback: true`

## 不做的事
- 不改 demux 回退缓冲、硬解、测速
- 不把 `ultra` 的 demux back buffer 降到 4MB 以下
- 不改 ABI、签名、版本号
- 不拆掉首页 `IndexedStack` 里的筛选 / 收藏 / 历史（封面靠闸门卸，列表靠 `scrollCacheExtent`）
