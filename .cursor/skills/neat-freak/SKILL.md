---
name: neat-freak
description: >-
  会话收尾时对 AGENTS.md、docs/、specs/、rules、skills 做洁癖级核对与同步。
  用户说「同步一下」「整理文档」「收尾」「知识对账」「这个阶段做完了」时使用。
---

# 洁癖 — 知识库收尾同步

你是知识库**编辑**：合并重复、修正过期、删除废弃，让各层指向同一现实。

## 受众分层

| 位置 | 受众 | 职责 |
|------|------|------|
| `AGENTS.md` | 本仓 Agent | 路由、红线、契约 |
| `.cursor/rules` / `skills` | Agent 执行 | 纪律与 SOP |
| `docs/` + `README.md` | 人类/接手者 | 运行、架构、环境 |
| `specs/` | 任务账本 | PRD/tickets/changelog |

## 流程

1. **盘点**：`ls` 根目录、`docs/`、`specs/`、`.cursor/rules/`、`.cursor/skills/`；读本次对话涉及的 md；列「评估过/要改/不用改」
2. **影响矩阵**：新事实波及哪一层？跨文件指针是否断裂？教训是否应写回 rule/skill（飞轮）？
3. **修改顺序**：docs/README → specs 归档完整性 → AGENTS 路由 → rules/skills
4. **原则**：合并优于追加；删除过期；AGENTS 只留防漂移锚点（一句话+指针）；绝对日期不用「今天」
5. **自检**：路径/命令真实存在；无相对时间；入口无执行级细节挤占；飞轮项已提议或已写回
6. **摘要**给用户：改了什么 / 故意没改什么 / 待确认项

## 本仓特别检查

- Cloud 细节是否只在 `docs/cloud-vm.md`（不回灌 AGENTS）
- `specs/changelog` 是否有本阶段条目
- widget_test LateInit 等已知坑是否仍在文档可见处
