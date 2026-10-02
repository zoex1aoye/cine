# 01 缓冲圈加载速度
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261001-08
- 依赖：无
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

`CineVideoControls`：缓冲 ≥~0.8s 显示「加载中 {速度|—}」；轮询 mpv `cache-speed`；移除弱网提示条。

## 验收

- [x] 弱网「网络较弱…」UI 已删
- [x] 0.8s 延迟后出现速度行；缓冲结束清除
- [x] 有速度格式化为 KB/s 或 MB/s；无数据为 —
- [x] `flutter analyze` 无 error
- [ ] 冒烟：seek/弱网缓冲可见速度（用户）
