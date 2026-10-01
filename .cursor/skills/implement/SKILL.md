---
name: implement
description: >-
  流水线步骤 4：按 PRD/tickets 实现。用户说「按 spec 实现」「implement」「开始做这个 ticket」时使用。
  编排 cine-flutter-dev、验证命令与收尾审查；不自动 commit。
---

# Implement

## 流程

0. **基线**：读 `AGENTS.md`、相关 rules；确认 Flutter 环境可运行。冲突以能跑通的配置为准并报告。

1. **读规格**：当前 ticket + 对应 PRD 片段。不清就问。按 tickets 时：
   - 读状态：`[x]` 跳过、`[~]` 接着做、`[ ]` 待做
   - **完成即**勾 `[x]` 与验收项；检查未绿禁止标完成
   - 只读当前票，禁止顺手做邻票范围蔓延

2. **装载**：`.cursor/skills/cine-flutter-dev`；碰播放器再守 `player-discipline`

3. **实现纪律**：
   - 先搜索同类实现再写
   - 测试接缝约定后：能写测则红→绿；现有 `widget_test` 有 LateInit 坑，新增测试须初始化 `MubuApiClient.instance`
   - 每改完相关文件跑 `flutter analyze`（无 error）

4. **验证**：票面验收 + `flutter analyze`；有测试则 `flutter test`；播放器改动冒烟一条流

5. **审查**：调用 `code-review`（固定点=本分支 merge-base 或用户指定）

6. **提交**：仅当用户明确指令；message 含 ticket 引用

## 禁止

- 实现 PRD/票面没有的东西
- 静默改 PRD；发现矛盾停问
- 自动 commit / push
