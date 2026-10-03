# 06 Code Review 修复清单
- 状态： [x] 完成
- PRD：PRD-20261003-02、PRD-20261003-03
- 依赖：01–05
- 栈位：全栈 / player
- 须装载：cine-flutter-dev

## 交付什么

### A 阻断
- [x] A1 `media_kit_player_stub.dart` 同步 `JpPlayer` 新成员（`supportsDecodeToggle` / `toggleDecodeMode` / `isHardwareDecodeNotifier` 改为抽象），`flutter analyze` 无 error
- [x] A2 `pubspec.lock` 回滚到 feature 基线（不随本地 SDK 漂移）

### B 硬解自愈
- [x] B1 `HwdecWatchdog`：以首帧（视频宽高）为信号，仅 `playing && !buffering` 计时
- [x] B2 回退状态收进实例；回退/手动切换保存进度与暂停态；`ensureProbed` 并发安全；解码偏好持久化
- [x] B3 release 日志回到 `warn`；初始软解路径同样下发 `vd-lavc-skiploopfilter`

### C TV 遥控与 UI
- [x] C1 播放页按键策略：焦点在根节点才处理方向/确认键，焦点在底栏时让出给焦点遍历
- [x] C2 解码按钮仅 `supportsDecodeToggle` 时显示，去掉多余 `FocusableActionDetector`

### D 内存档位
- [x] D1 新增 ultra 档（`totalMem <= 1.2GB`），constrained 恢复基线预算
- [x] D2 封面只传 `memCacheWidth`；TV 封顶只看内存档；图片缓存按字节预算
- [x] D3 `trimImageCacheOnPlayerEnter` 仅受限档 `clear()`，不用 `clearLiveImages`
- [x] D4 去掉无效的 `demuxer-donate-buffer` 与对 MediaCodec 无效的 `hwdec-extra-frames` 收紧

### E 构建与文档
- [x] E1 TV manifest 去掉多余 `LAUNCHER` / `largeHeap` / `hardwareAccelerated`
- [x] E2 ABI 解析去掉透传分支，PRD 补决策记录
- [x] E3 CI 按 flavor 构建
- [x] E4 测试：删自证测试，补看门狗 / 按键策略 / 档位 / 图片缓存的真实测试
- [x] E5 文档对账（ticket 标题、PRD 勾选、changelog）

## 未验证（需实机 / CI）
- [ ] 目标 SoC 上 `estimated-vf-fps` 的行为、看门狗与回退的真实表现
- [ ] TV 遥控器走通 `↑` 进控件栏 → 切换解码 → 返回
- [ ] `flutter build apk --flavor mobile|tv`（本环境无 Android SDK）与 Kotlin 编译

## 不在本票范围
- Impeller 全局关闭（需确认 Fire HD 场景后再决定是否收敛到 tv flavor）
- 进度条拖动不暂停的实现（需实机验证）
- `TvShortcutsShell` 冗余（无实机证据不删）
