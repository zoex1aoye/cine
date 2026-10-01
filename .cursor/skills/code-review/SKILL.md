---
name: code-review
description: >-
  双轴代码审查：Standards（编码标准）与 Spec（规格符合度）。用户说「代码审查」
  「review 代码」「审查这次改动」「code review」时使用。对固定点到 HEAD 的 diff 分轴报告。
---

# Code Review — 双轴审查

## 1. 锁定固定点

用户给 commit/分支/tag；未给则问（常用 `main`）。

```bash
git rev-parse <fixed-point>
git diff <fixed-point>...HEAD
git log <fixed-point>..HEAD --oneline
```

坏引用或空 diff → 在此失败，不往下。

## 2. 找规格

顺序：commit 里的 `specs/tickets` / `PRD-` 引用 → 用户给的路径 → `specs/prd/`。没有则 Spec 轴跳过并注明。

## 3. 找标准

- `AGENTS.md` 红线
- `.cursor/rules/flutter-structure.mdc`、`player-discipline.mdc`、`workflow.mdc`
- diff 含 `lib/player/**` 时强制对照 player 纪律

**味道基线**（判断，非硬违规；仓库文档标准优先）：Mysterious Name、Duplicated Code、Feature Envy、Data Clumps、Primitive Obsession、Repeated Switches、Shotgun Surgery、Divergent Change、Speculative Generality、Message Chains、Middle Man。

## 4. 两轴报告（可并行子代理）

**Standards**：硬性违反（引用 rule 文件）+ 味道判断；跳过工具已强制项；≤400 字/轴为宜。

**Spec**：缺失需求 / 范围蔓延 / 实现疑错；引用 PRD/ticket 行。

## 5. 聚合

分 `## Standards` / `## Spec` 呈现，**不要合并成单一优先级列表**。结尾各轴发现数 + 各轴最严重一条。

## 验证附注（本仓）

审查同时提醒：`flutter analyze` 是否无 error；播放器 diff 是否已冒烟。
