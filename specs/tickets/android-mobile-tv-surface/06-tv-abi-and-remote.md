# 06 TV 32/64 位包与遥控焦点
- 状态： [x] 完成
- PRD：PRD-20261002-05
- 依赖：01, 04, 05
- 栈位：全栈
- 须装载：cine-flutter-dev

## 交付什么
电视实机确认可安装 32 位应用。CI 同时产出 TV `armeabi-v7a` 与 `arm64-v8a`。分类筛选与播放详情在未进入内部全屏时用方向键走焦点，播控键只在内部全屏生效。

## 验收
- [x] mobile 仍只含 `arm64-v8a`；tv flavor 含 `armeabi-v7a` + `arm64-v8a`
- [x] workflow 打出 mobile arm64、tv v7a、tv arm64 三个 APK，且带对应 `--flavor` / `CINE_SURFACE`
- [x] 分类轨、筛选分类芯片、筛选条件与选项可聚焦；OK 激活；隐藏 Tab 不参与焦点
- [x] 播放详情未内部全屏：返回、收藏、播放、全屏、线路、剧集可聚焦
- [x] 内部全屏仍为左/右 seek、上/下音量、OK 播放暂停、Back 退出全屏
- [x] `flutter analyze` 无 error

## 笔记
手机不打 32 位，避免多 ABI 包在部分机型上抽到 v7a 兼容库。TV 用 `--split-per-abi`，与 flavor `abiFilters` 对齐。
