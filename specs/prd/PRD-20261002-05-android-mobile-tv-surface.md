# Android mobile/tv 双线 + 低端自适应
- 编号：PRD-20261002-05 ｜ 确认人：用户 ｜ 档位：中型×碰播放器·共享组件 ｜ 栈位：全栈

## 要解决什么问题（1 段）

幕布需在可侧载的 Android 投影/TV 上可用：打包区分手机/平板与 TV；TV 侧重遥控器焦点；低内存机共用「受限档」收缩 demux/图片缓存，并对 Android 硬解做探测与一次软解回退。

## 用户故事与验收标准
作为观众，我想要按设备形态安装对应 APK，并在低内存或硬解异常时仍能浏览与播放，以便投影机/TV 侧载可用。
- [x] `mobile` / `tv` 两 flavor 均可打出 release APK；tv 包 applicationId 带 `.tv`，含 LEANBACK_LAUNCHER（leanback `required=false`）
- [x] Dart 侧 `CINE_SURFACE` 区分 UI/焦点策略；手机包不强制 D-pad 漫游
- [x] `totalMem < 2GB`（或等价探测）进入 constrained：demux 缓冲下调、封面 memCache 约束、imageCache 上限下调、首页 KeepAlive 收敛
- [x] Android：MediaCodec 探测无硬解则 `hwdec=no`；有则尝试硬解，失败最多 reopen 软解一次
- [x] TV：浏览态可用方向键聚焦导航与影片卡并激活；播放页左右 seek、上下音量、OK 播放暂停、Back 退出
- [x] `flutter analyze` 无 error

## ATDD
| 场景 | 给定条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| 双包 | 工程可编 | `flutter build apk --flavor mobile/tv …` | 两 APK 产出，命名含 surface |
| TV 入口 | tv 包 | 安装到支持 Leanback 或普通 Android | 桌面可见启动项；无 leanback 特性也可装 |
| 受限缓冲 | constrained | 打开播放 | demux 前向/后向上限明显低于 normal 移动端 |
| 硬解回退 | 硬解黑屏/失败 | 开播 | 至多 reopen 一次走软解 |
| TV 遥控 | tv surface | 方向键浏览并进播放 | 焦点可见；键位符合上表 |

## 决策记录
| # | 议题 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| 1 | 产品形态 | mobile/tv 分线打包 | 用户拍板 | 2026-10-02 |
| 2 | 投影默认包 | tv | 遥控器为主 | 2026-10-02 |
| 3 | leanback required | false | 投影机常无正式 Leanback | 2026-10-02 |
| 4 | 入口 | 单 main + dart-define | 防双入口漂移 | 2026-10-02 |
| 5 | 受限档作用域 | 两线共用运行时探测 | 低端手机也受益 | 2026-10-02 |
| 6 | 硬解开关系列 | 本期不做用户开关 | 防范围膨胀 | 2026-10-02 |

## 范围
| 含 | 不含 |
|---|---|
| Android flavors + Manifest | iOS/桌面 flavor |
| DeviceProfile + 内存收缩 | armeabi-v7a（除非实机非 arm64） |
| hwdec 探测与一次回退 | 商店上架/EPG/推荐行重做 |
| TV 浏览+播放焦点键位 | 设置页「强制软解」 |

## 风险与回滚
- Flavor 导致默认 `flutter run` 缺 flavor → README/注释写清 `--flavor mobile`
- 硬解 reopen 闪断 → 仅失败路径触发且最多一次
- 回滚：去掉 flavor 源集与 `CINE_SURFACE` 分支即可恢复单包

## 实现约束
- 引用：`.cursor/rules/flutter-structure.mdc` / `player-discipline.mdc` / `git-conventions.mdc`
- 须装载技能：cine-flutter-dev；改 player 守条件编译成对

## 不做的事
- 完整 Google TV 认证与商店物料
- 用户设置里的强制软解开关
- 回补 32-bit ABI（无实机证据前）
