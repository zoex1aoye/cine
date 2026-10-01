---
name: rules-authoring
description: >-
  创建或调整 .cursor/rules/ 下 .mdc 规则。典型触发：从 AGENTS 拆文件纪律、
  调整 alwaysApply/globs、与 AGENTS 重复需收敛。
---

# Rules 编写（Cursor）

## 判断标准

「是否只针对某类文件？」→ rules（globs）；每次都要知道 → AGENTS；某类任务 → skill。

## Frontmatter

```yaml
---
description: 一句话
globs: lib/**/*.dart   # 文件型
alwaysApply: false     # 或 true 常驻
---
```

| alwaysApply | globs | 行为 |
|---|---|---|
| true | 任意 | 始终注入 |
| false | 有值 | 匹配文件时 |
| false | 无 | 无效 |

常驻规则建议 ≤5 个、每个几十行；path 规则 20–80 行。

## 红线

禁止软性描述；每条可执行。与 AGENTS 单一出处。改前向用户报告方案。
