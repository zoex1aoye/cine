# TV 1GB 内存侧载优化与性能增强
- 编号：PRD-20261003-02 ｜ 确认人：用户 ｜ 档位：中型×碰播放器·跨平台 ｜ 栈位：全栈

## 要解决什么问题（1 段）

针对非 Google 商店、通过纯侧载安装的 1GB 内存低端 Android TV / 投影仪：新增 `ultra` 内存档承接 1GB 级设备的激进预算（demux 缓冲、图片缓存、封面解码宽度），进播放页时释放首页闲置封面，把物理内存让给视频解码器；同时保证 TV 包在 Leanback 桌面与普通 AOSP 桌面都能看到启动图标。

## 用户故事与验收标准

作为 1GB 侧载电视/投影仪用户，我希望安装 TV 版 APK 后在任意桌面都能看到应用图标，且在浏览海报和播放高清视频时不发生卡死或 OOM 崩溃。

- [x] 侧载安装后 Leanback 桌面与普通 AOSP 桌面均显示图标：普通 `LAUNCHER` 由 `main` 清单的 `MainActivity` 提供，`tv` flavor 合并后再叠加 `LEANBACK_LAUNCHER`；配置 TV 横幅 `android:banner`
- [x] 内存分三档：`ultra`（`totalMem <= 1.2GiB` 或系统 low-ram）、`constrained`（`< 2GiB`）、`normal`；预算集中在 `DeviceBudget`，native / stub 共用
- [x] `ultra`：`ImageCache` 24MB；封面解码宽度上限 180px；demux 前向 8MB / 后向 4MB
- [x] `constrained`：`ImageCache` 48MB；封面解码宽度上限 240px；demux 前向 10MB / 后向 6MB
- [x] 封面解码上限只看内存档，不看 TV/手机 surface（4GB 的 TV 不被糊化）；只传 `memCacheWidth`，避免同时传宽高被拉伸变形
- [x] 进入播放页时受限档调用 `ImageCache.clear()` 释放闲置封面；不使用 `clearLiveImages()`（Flutter 文档：不缓解内存压力）
- [x] `flutter analyze` 无 error；相关单元测试与 Widget 测试通过

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 侧载桌面可见性 | 普通 AOSP 桌面或 Leanback 桌面 | 侧载安装 TV 包 | 两类桌面均能检索到启动入口 |
| 1GB 档位 | `totalMem <= 1.2GiB` | 启动应用 | tier=ultra，`ImageCache` 24MB，封面解码宽 <= 180 |
| 2GB 以下 | `1.2GiB < totalMem < 2GiB` | 启动应用 | tier=constrained，沿用基线预算 |
| 大内存 TV | `totalMem >= 2GiB` 且为 tv 包 | 浏览海报 | 封面按常规上限解码，不被压到 180 |
| 播放期内存回收 | 受限档，列表点击进入播放 | 进入播放页 | 空闲封面被驱逐，仍在屏幕下层的封面保持缓存追踪 |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | 普通 LAUNCHER | 不在 tv 清单重复声明 | `main` 清单已声明，flavor 合并后并存 | 2026-10-03 |
| 2 | `largeHeap` / `hardwareAccelerated` | 不加 | `largeHeap` 只放大 Java 堆，mpv/Flutter 在原生内存；`hardwareAccelerated` 默认即 true | 2026-10-03 |
| 3 | `demuxer-donate-buffer` | 不设置 | mpv 默认 yes，语义是「后向缓冲借用前向缓冲空闲额度」，不归还物理内存 | 2026-10-03 |
| 4 | `hwdec-extra-frames` | 不再为 1GB 单独收紧 | mpv 手册：仅对需预分配表面的 API（d3d11va/vaapi）生效，对 MediaCodec 无影响 | 2026-10-03 |
| 5 | 32 位 ABI | 允许 `-Ptarget-platform=android-arm` 打 `armeabi-v7a`，默认仍 arm64 | 部分 1GB 电视为 32 位固件；与 PRD-20261002-05「无实机证据前不回补」冲突，**须在合入前补实机证据** | 2026-10-03 |
| 6 | 图片缓存预算 | 以字节为主，张数放宽到 100 | 封面已按 memCacheWidth 缩小，30 张会让 TV 多行海报反复驱逐重解码 | 2026-10-03 |
| 7 | ultra 后向缓冲 | 4MB（不低于） | 5–8Mbps 约 4–6 秒；再小则 TV「左键 -10s」每次回源 | 2026-10-03 |

## 范围
| 含 | 不含 |
|---|---|
| TV 清单 Leanback 入口与横幅 | 商店审核与 Google TV 认证流程 |
| ultra 档预算与进播放页释放封面 | 重构整站 UI 架构 |
| 封面解码宽度与图片缓存预算 | 外部第三方播放器插件更换 |

## 风险与回滚
- 档位阈值依赖 `ActivityManager.getMemoryInfo().totalMem` 与 `isLowRamDevice()`，实机分档需在目标设备上确认
- 回滚：`DeviceBudget` 三档取值回退为同一份即可恢复单档行为
