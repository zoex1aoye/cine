# 幕布 (Cine)

![幕布 (Cine)](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-crimson?style=for-the-badge&logo=flutter)

幕布 (Cine) 是一款基于 Flutter 与 `media_kit` (MPV 核心) 打造的高颜值、轻量级跨平台影视客户端。本项目专注于提供流畅的影视浏览、多维度智能筛选、本地播放记录以及极速的线路切换体验。

---

## 🌟 核心特色

* 🎬 **极致播放体验**：集成原生 `libmpv` 播放内核，完美支持 Linux 平台上的 **VA-API 硬件解码**，大幅降低播放高码率 M3U8 流时的 CPU 占用与发热量。
* ⚡ **多线路智能测速**：内置并发多路测速机制，自动选择延迟最低的绿色通道；右上角悬浮切线面板支持**一键热切换线路**。
* 🎨 **现代美学设计**：深色调沉浸式 UI，首页大图横幅配备毛玻璃底衬，支持启动分类加载骨架屏与测速雷达呼吸脉动特效。
* 📱 **响应式自适应布局**：自动适配桌面端（宽屏左侧导航栏）与移动端（窄屏底部导航栏及横向滑块），实现多端排版无缝过渡。
* 🔍 **智能多维筛选**：引入面包屑筛选机制（分类、地区、年份、排序），针对短剧和纪录片做了深度 ThinkPHP 服务端适配，彻底解决搜索漏传报错。
* 📝 **本地缓存与收藏**：支持影片本地一键收藏（Bookmark）和播放历史记录（History），点击头像拉开毛玻璃下拉菜单即可快速直达。

---

## 🚀 运行与安装

### 系统要求
* **操作系统**：Linux (Ubuntu/Fedora/Arch 等桌面版)、Windows 或 macOS。
* **硬件解码支持**：Linux 环境下推荐安装 `va-driver` / `intel-media-driver` / `mesa-va-drivers` 保证显卡 VA-API 硬件加速生效。
* **依赖库**：系统需安装有 `libmpv.so`（通常随 mpv 播放器一同安装，如 `sudo apt install mpv`）。

### 开发者编译指引

#### 环境要求

- Flutter SDK (推荐使用最新稳定版)
- 已安装 `libmpv.so`（如 `sudo apt install mpv`）
- Linux 桌面环境推荐安装 VA-API 驱动（`mesa-va-drivers` / `intel-media-driver`）

#### 构建 Android 版本

```bash
# 1. 确保 Android 配置已更新
#    settings.gradle.kts:  org.jetbrains.kotlin.android → 最新版本
#    app/build.gradle.kts:  compileSdk → 最新 SDK 版本
#    gradle-wrapper.properties:  Gradle 版本与 Kotlin 兼容

# 2. 构建 APK
flutter build apk --release --target-platform android-arm64
```

> **注意**：如果遇到 Kotlin 编译错误，通常是因为 pub.dev 上的插件使用了更新的 Kotlin 版本。请同步升级 `android/settings.gradle.kts` 中的 Kotlin 插件版本和 Gradle 版本，参见 [Kotlin 版本列表](https://kotlinlang.org/docs/releases.html)。

#### 完整开发笔记

请参考给开发者编写的 [开发笔记与逆向报告](devnotes.md)。

---

## 🎮 播放器操控指南

在播放页面，界面操作与快捷键经过深度的优化，使用更加得心应手：

### 鼠标与界面操作
* **唤出控制面板**：在视频区域**移动鼠标**或**单击画面**，即可唤出底部进度条、播放状态及右上角线路切换按钮。
* **双击画面**：切换全屏/退出全屏。
* **右上角线路徽标**：显示当前可用的健康线路总数（如 `3条`）。点击可展开精美的暗色毛玻璃悬浮下拉列表，直观查看看各线路测速延迟（绿、橙、红）并一键切换。

### 键盘快捷键（原生支持）
* `Space (空格键)`：播放 / 暂停。
* `Enter (回车) / F`：切换全屏。
* `Left (左方向键)`：快退 10 秒。
* `Right (右方向键)`：快进 10 秒。
* `Up (上方向键)`：音量调大。
* `Down (下方向键)`：音量调小。

---

## 📅 最新更新日志

### [2026-06-10] 播放体验与细节优化
1. **测速雷达呼吸光晕**：优化了加载时的同心测速 HUD (`ConcentricHud`)。为其增加了与播放按钮一致的动态扩展红色脉冲光环和呼吸投影，告别冰冷的加载等待。
2. **电影卡片垂直居中**：优化了影视卡片底部的文字排版。当影片没有上映年份及分类（仅标题）时，自动隐藏副标题及间距，使单行标题完美在卡片底部垂直居中。
3. **Tab 切换竞态自愈**：解决了在首页左侧大类快速切换时，慢请求数据覆盖新 Tab 导致界面渲染错乱的 Race Condition 问题。现在页面内容能 100% 紧跟用户的点击焦点。
4. **统一可用线路统计**：右上角切换线路角标由显示总物理线路（包含失效和超时线路）修改为只统计“当前可用健康线路数”，保证数目同下拉列表中的选项完全一致。
5. **修复控制按钮消失 bug**：解决了播放开始后无法使用快进、全屏、设置等快捷控制面板的顽疾。现在封面遮罩与模糊层在淡出后会自动忽略指针事件 (`IgnorePointer`)，让操作手势完美穿透至底层播放器。
