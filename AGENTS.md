# AGENTS.md — 幕布 (Cine)

> 本文件每轮对话自动注入。**只做路由 + 红线 + 协作契约**。深知识在 `docs/`，流水线交接物在 `specs/`，机器纪律在 `.cursor/rules/`，任务技能在 `.cursor/skills/`。
> 技术底座：Flutter（SDK ^3.7）单仓跨平台影视客户端；播放内核 `media_kit` / libmpv；本地状态 Hive；远端 API 启动时自动发现（见 `lib/api/jp_api.dart`）。本仓无后端。

## 一、开工协议

1. 首轮判断本次任务**档位**（体量：小修/中型/大型 × 影响：常规/碰播放器·API·共享组件/跨平台）与**栈位**（player / api / ui / 全栈 / 非代码），不确定就问
2. 一切任务走**七步精简流水线**（单一真相源：`.cursor/rules/execution-discipline.mdc`）：开场 → 需求规格 → 拆票 → 实现 → 审查+验证 → 归档 → 收尾。进步骤须出示上一步产出物编号；**用户明示跳过除外**

## 二、路由表（何时读什么）

| 你要做的事 | 先读 |
|---|---|
| 任何 Flutter 开发 | `.cursor/skills/cine-flutter-dev` + `.cursor/rules/flutter-structure.mdc` |
| 播放器 / 全屏 / 控件 / 硬解 / TV 遥控 | `.cursor/rules/player-discipline.mdc` + `lib/player/` |
| Android 打包 / TV flavor / ABI | `.cursor/rules/android-tv-packaging.mdc` |
| API / 测速 / 签名 / 线路 | `lib/api/`（入口 `jp_api.dart`、`mubu_api_client.dart`） |
| 提需求 / 开工 | `.cursor/skills/opening-protocol` |
| 出 PRD / 拆票 / 实现 / 审查 | `.cursor/skills/to-prd` → `to-tickets` → `implement` → `code-review` |
| 盘问方案 / 钢人取舍 | `.cursor/skills/grill-me` / `steelman` |
| 改规范 / 规则 / 技能 | `.cursor/skills/agents-md-authoring` / `rules-authoring` / `skill-authoring` |
| 会话收尾 / 文档对账 | `.cursor/skills/neat-freak` |
| Cursor Cloud Linux VM 环境 | `docs/cloud-vm.md` |
| Hook（开工注入 / 飞轮提示） | `.cursor/hooks.json` + `.cursor/hooks/` |

## 三、红线（违反 = 立即停止并报告）

1. **密钥与签名**：API secret、签名盐、硬编码口令禁止入库外泄；改签名逻辑须对照 `lib/api/jp_api.dart` 现有口径，禁止凭记忆重写
2. **平台条件编译**：`*_native.dart` / `*_stub.dart` 成对出现；改平台 API 须同步 stub，并验证 `dart.library.html` 导出入口
3. **播放器边界**：seek-preview 缩略图仅在**内部全屏**（`VideoState.isFullscreen()`）渲染，不是窗口管理器全屏；TV 未全屏时方向键走焦点，seek/音量只在内部全屏；硬解/locale 改动须分平台核对
4. **Android ABI**：禁止写 `ndk.abiFilters`（与 `--split-per-abi` 冲突，且 splits 是工程级的）。电视 32/64 位只通过 workflow 的 `--target-platform` 产出
5. **API 客户端初始化**：测试或独立 pump Widget 前必须完成 `MubuApiClient.instance` 赋值（`main()` 里设的）；禁止直接 pump `MubuApp` 而不初始化
6. **提交**：AI 不自动 commit——须用户明确指令；commit 格式 `type(scope): 中文描述`，有任务单时附 `[#specs/tickets/…]`
7. **规范治理**：rules / skills / AGENTS.md 变更走 PR 或用户确认；同一坑出现 2 次当场写回规范（飞轮）
8. **机器路径**：禁止写死本机绝对路径；命令与说明须跨 macOS / Linux / Windows 可读

## 四、团队协作契约

- **分支**：`feature|bugfix|hotfix/<YY/MM>/<kebab-desc>`；不直接在 `main` 开发（细则 `.cursor/rules/git-conventions.mdc`）
- **提交纪律**：用户单次授权仅限单次；历史整洁优先 rebase 同步、语义化 merge
- **规约分层**：skills = 任务 SOP；rules = 文件/常驻纪律；冲突以本仓 rules + AGENTS 为准
- **档位伸缩**：小修档最小产出见 execution-discipline；碰 `lib/player/**`、`lib/api/**` 或跨 3+ 目录自动升影响档
- **验证命令**：`flutter analyze`；`flutter test`；桌面跑 `flutter run -d macos|linux|windows`（按本机）；改播放器须真机/桌面冒烟播一条流
- **统一中文回复**：代码/命令/标识符可英文

## 五、目录速览

`lib/api/`（远端 API + 存储门面）· `lib/models/`（DTO + Hive adapter）· `lib/pages/`（路由页）· `lib/player/`（media_kit 封装与控件）· `lib/widgets/`（可复用 UI）· `lib/utils/`（测速/选源/平台）· `docs/` · `specs/`（prd / design / tickets / changelog）· `.cursor/rules/` · `.cursor/skills/`
