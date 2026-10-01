# 02 线路列表面板与冒烟
- 状态： [x] 完成（冒烟待用户确认）
- PRD：PRD-20261001-04
- 依赖：01
- 栈位：player
- 须装载：cine-flutter-dev

## 交付什么

切换线路面板基于回退后的代表源展示全部 usable 线路；macOS 冒烟确认蜡笔小新多线可见且无永久检测中。

## 验收

- [x] 线路列表对「无当前集名但该线有源」的线路不再因代表源为 null 被整行隐藏（代表源回退即可）
- [x] `_isLineUsable` / `_lineSpeed` / `_lineQualityCaption` 使用回退代表源
- [x] 单测：异名多线路在任意 scope 下均可 resolve（`film-style unique lines…`）
- [ ] macOS 冒烟：`蜡笔小新：灼热的春日部舞者们` 切换线路 >1 条，结束后非「检测中…」
- [x] `flutter analyze` 无 error

## 笔记

01 改代表源后面板自动修好；请本机打开该片点「切换线路」确认。
