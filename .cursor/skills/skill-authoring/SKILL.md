---
name: skill-authoring
description: >-
  创建或调整 .cursor/skills/*/SKILL.md。典型触发：封装任务 SOP、诊断不触发、
  超过 200 行需拆 references、防止变成第二个 AGENTS。
---

# Skill 编写（Cursor）

## 判断标准

「只有这类任务才需要？」→ skill。大量背景 → `references/`。

## 命名

按**任务意图**：`opening-protocol`、`cine-flutter-dev`。禁止纯技术名堆砌成大而全手册。

## 结构

```
.cursor/skills/my-skill/
├── SKILL.md          # 50–200 行 SOP
└── references/       # 按需读
```

## Frontmatter

```yaml
---
name: my-skill
description: >-
  做什么。用户说「…」或改 … 时使用。（含 WHAT + WHEN）
---
```

description 用第三人称、含触发词；决定能否被选中。

## 红线

无软性描述；验证步骤具体（`flutter analyze` 等）。一个 skill 一个工作意图。
