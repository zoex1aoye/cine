---
name: to-tickets
description: >-
  流水线步骤 3：把 PRD/计划拆成 tracer-bullet tickets，落 specs/tickets/。
  用户说「拆任务」「拆 tickets」「分成可执行任务」时使用。
---

# To Tickets

## 流程

1. **读 PRD**（无编号则退回 `to-prd`）
2. **探索代码**，用本仓术语（线路、测速、内部全屏、Hive box 名等）
3. **垂直切片**：每票窄而完整、可独立演示、能塞进一个上下文窗口
   - 功能类：穿透相关层（如 api+page+widget）
   - 基建/规范类：一票一关注点，可独立验证
4. **DAG**：`依赖：01, 02` 显式编号；无环；只写真门控依赖
5. **考用户**：粒度、依赖、合并/拆分 → 批准后再落盘
6. **落盘**：`specs/tickets/<feature-slug>/<NN>-<slug>.md`，模板见 `specs/tickets/TEMPLATE.md`

## 状态字段

`[ ]` 待做 · `[~]` 进行中 · `[x]` 完成。实现时完成即改状态。

## 大爆炸半径

全仓重命名等用 expand–contract：先扩张 → 分批迁移 → 收缩；勿硬塞单票。

## 自检

- [ ] 每票有 PRD 编号与验收勾选
- [ ] 阻塞者编号小于被阻塞者
- [ ] 票面写明栈位与须装载技能（通常含 `cine-flutter-dev`）
