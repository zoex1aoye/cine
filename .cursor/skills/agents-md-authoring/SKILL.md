---
name: agents-md-authoring
description: >-
  创建、瘦身或重构本仓 AGENTS.md。典型触发：超 250 行、与 rules 重复、/init、审查分层合理性。
---

# AGENTS.md 编写

## 唯一判断标准

「不管今天开发什么，这条都必须知道吗？」
- 是 → AGENTS.md
- 只针对某类文件 → `.cursor/rules/`
- 只针对某种任务 → `.cursor/skills/`

## 认知链条

仓库是什么 → 模块边界 → 架构禁区 → 怎么验证

章节：开工协议 / 路由表 / 红线 / 协作契约 / 目录速览。禁止软性描述与任务 SOP 正文。

## 调整流程

逐节标重复/软性/超预算 → 迁 rules 或 skill → 用户确认后执行 → 复核单一出处。

## 自检

- [ ] 约 100 行内（本仓目标）
- [ ] 与 rules/skills 无重复维护
- [ ] 命令可执行；Cloud 细节在 `docs/cloud-vm.md`
