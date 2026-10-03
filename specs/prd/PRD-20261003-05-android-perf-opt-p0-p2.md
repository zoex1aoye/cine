# Android 移动端与 TV/投影深度性能优化（P0–P2）
- 编号：PRD-20261003-05 ｜ 确认人：用户 ｜ 档位：大型×碰播放器与 Android 原生 ｜ 栈位：全栈 / player + ui

## 要解决什么问题
在 Android 平台（覆盖普通手机、平板以及内存 ≤1.2GB/2GB 的低配电视机顶盒/投影仪）上：
1. **内存压力与 OOM**：Android 系统在应用切后台或前台内存吃紧时会触发 `onTrimMemory`，之前 Dart 侧未监听该系统回调，导致图片缓存堆积最终引发 LMK（Low Memory Killer）直接杀死进程；
2. **离屏渲染与卡顿发热**：播放页背景及弹层存在的 `BackdropFilter` 实时高斯模糊在低端 Mali/PowerVR GPU 上触发双向多抽样卷积离屏层，导致严重掉帧发热；
3. **后台空转**：应用进入后台或锁屏时，底层解码器未联动挂起，白白消耗电量与发热；
4. **长列表重绘风暴**：海报卡片与瀑布流在焦点变换或局部微动效时缺乏 `RepaintBoundary` 隔离，触发大面积重绘；
5. **软解回退下的低端机卡顿**：硬解假死自愈回退到软解后，四核低频 A53/A35 等低端芯片算力不足导致音画不同步。

## 用户故事与验收标准
- **P0 阶段（内存与发热首要治理）**：
  - [x] 作为 Android 用户，当设备内存告急或切换后台时，应用能通过 `onTrimMemory` 主动释放未引用的非 live 封面缓存，避免进程被系统强杀。
  - [x] 作为 Android 用户，当应用切入后台非活跃态时，播放内核自动暂停解码，返回前台恢复，避免后台空转发热。
  - [x] 作为 Android 用户，进入播放页后，背景及加载遮罩在 Android/受限设备上完全停用 `BackdropFilter` 离屏模糊，降级为高性能纯色/静态半透明遮罩。
- **P1 阶段（图层隔离与软解降载）**：
  - [x] 作为用户，在首页海报瀑布流滚动与卡片聚焦时，单张卡片的变化被 `RepaintBoundary` 隔离，不引起全屏幕图层反复重绘。
  - [x] 作为低端 Android 电视/投影用户，在软解模式或硬解回退下，对受限机型自动启用非关键帧环路去块滤波跳过（`vd-lavc-skiploopfilter=nonkey`），保证流畅不卡顿。
- **P2 阶段（架构与数据层轻量化）**：
  - [x] 作为用户，本地收藏与历史记录在大数据量下平滑分页渲染，不造成首屏阻塞；构建配置规范精简。

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|---|---|---|---|
| 1. 系统内存修剪 | Android 运行应用，加载多张海报后触发 `TRIM_MEMORY_UI_HIDDEN` | 切后台或系统发广播 | Native 通过 MethodChannel 唤起 Dart `PaintingBinding.instance.imageCache.clear()` |
| 2. 切后台暂停 | Android 正在播放视频 | 按 Home 键或切应用 | 应用监听生命周期，播放器自动暂停；回前台时恢复播放 |
| 3. 播放页毛玻璃消除 | Android 运行播放页 | 打开任意视频 | 背景与缓冲层均走 `ColoredBox`，无 `BackdropFilter` 离屏合成 |
| 4. 瀑布流图层隔离 | 首页滚动列表 | 快速上下滑动与卡片聚焦 | 每张卡片享有独立 `RepaintBoundary` |
| 5. 软解滤波优化 | 受限 Android 设备或用户强制软解 | 起播视频 | 播放器内核注入 `vd-lavc-skiploopfilter=nonkey`，解码负载显著减轻 |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | onTrimMemory 级别映射 | `UI_HIDDEN` 与 `CRITICAL`/`COMPLETE` 触发清除非 live 缓存 | `clear()` 只驱逐空闲项，不影响前台正在显示的 live 视图 | 2026-10-03 |
| 2 | 切后台是否自动暂停 | 非桌面端切入 `paused` 时暂停并记录，`resumed` 时恢复 | 避免手机/平板切后台持续消耗解码算力和电池 | 2026-10-03 |
| 3 | BackdropFilter 策略 | Android 平台或受限档完全替换为静态半透明遮罩 | 移动端低端 GPU 的 Shader 卷积是掉帧主因 | 2026-10-03 |

## 实现约束
- 引用规则：`.cursor/rules/flutter-structure.mdc`、`.cursor/rules/player-discipline.mdc`
- 须装载技能：`cine-flutter-dev`
- 保持 `media_kit_player_native.dart` 与 `media_kit_player_stub.dart` 接口一致。

## 不做的事
- 不直接在 Android manifest 开启 `largeHeap="true"`（掩盖内存泄漏且增大 GC 暂停）。
- 不破坏现有画质与清晰度，降采样尺寸严格按照 `DeviceBudget.coverDecodeWidth` 约束。
