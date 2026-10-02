# 03 Android hwdec 自适应
- 状态： [x] 完成
- PRD：PRD-20261002-05
- 依赖：02
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么
Android 上 MediaCodec 探测 + 硬解尝试；失败最多 reopen 软解一次；constrained 降低 hwdec-extra-frames。

## 验收
- [x] `hwdec_policy`（或等价）封装探测结果与回退状态
- [x] 无硬件 H.264/HEVC → 直接 `hwdec=no`
- [x] 有则 `amediacodec,mediacodec`；失败路径 reopen 一次 `hwdec=no`
- [x] constrained：`hwdec-extra-frames` 为 1–2
- [x] 仅改 Android 分支；native/stub 签名一致
- [x] `flutter analyze` 无 error

## 笔记
遵守 player-discipline；防死循环 reopen。
