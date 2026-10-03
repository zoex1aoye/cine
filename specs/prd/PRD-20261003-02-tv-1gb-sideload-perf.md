# TV 1GB 内存侧载优化与性能增强
- 编号：PRD-20261003-02 ｜ 确认人：用户 ｜ 档位：中型×碰播放器·跨平台 ｜ 栈位：全栈

## 要解决什么问题（1 段）

针对非 Google 商店、通过纯侧载安装的 1GB 内存低端 Android TV / 投影仪，优化侧载桌面入口兼容性（防止普通 Android 桌面下找不到 App 图标）、增加 TV 横幅声明与大堆内存权限；进一步收缩 1GB 极限受限档下的 Flutter 图片缓存、封顶封面图片解码尺寸并在进播放页时主动回收闲置图片内存；优化底层播放器 demuxer 内存释放与精简流缓冲，确保 1GB 低内存电视侧载后启动快、桌面可见、播放不爆 OOM。

## 用户故事与验收标准

作为 1GB 侧载电视/投影仪用户，我希望安装 TV 版 APK 后在任意桌面都能看到应用图标，且在浏览海报和播放高清视频时不发生卡死或 OOM 崩溃。

- [ ] 侧载安装后在标准 Leanback 电视桌面与普通第三方 AOSP 桌面均显示应用图标（双 Launcher Intent Filter 支持）；配置 TV 大横幅。
- [ ] TV flavor 开启 `largeHeap="true"` 与 `hardwareAccelerated="true"`。
- [ ] 针对 1GB 设备，`DeviceProfile` 支持超受限/1GB 档位内存预算：`PaintingBinding.imageCache` 上限进一步收紧至 30 张 / 24MB；TV 模式封面强制限制解码宽度（最大 180px）。
- [ ] 播放页初始化及进入全屏时主动触发图片内存回收（`clearLiveImages`），将物理 RAM 释放给视频解码器。
- [ ] Native 播放器配置：启用 `demuxer-donate-buffer=yes`，1GB/受限档进一步压缩前向与后向缓冲区，平稳利用 MediaCodec 硬解。
- [ ] `flutter analyze` 无 error；相关单元测试与 Widget 测试全部通过。

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 侧载桌面可见性 | 普通 AOSP 桌面或 Leanback 桌面 | 侧载安装 TV 包 | 两类桌面均能检索到启动入口 |
| 1GB 内存预算 | 1GB 内存设备 (totalMem <= 1.2GB) | 启动应用 | `imageCache` 最大 30 张 / 24MB，封面 memCache 约束生效 |
| 播放期内存回收 | 用户从列表点击进入播放 | 进入播放页 | 触发图片缓存清理，避免与解码器争抢 RAM |
| 播放内核优化 | 低内存下播放网络流 | 播放器启动 | 启用 `demuxer-donate-buffer`，减少内存常驻 |

## 范围
| 含 | 不含 |
|---|---|
| TV Manifest 双 Launcher 与大横幅 | 商店审核与 Google TV 认证流程 |
| 1GB 级图片缓存收缩与进播放页主动 GC | 重构整站 UI 架构 |
| native 解码缓冲精简与 buffer donate | 外部第三方播放器插件更换 |
