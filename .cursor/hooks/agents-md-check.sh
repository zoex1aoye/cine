#!/usr/bin/env bash
# sessionStart hook：探测本仓约定，经 additional_context 注入开工必读提醒。
# 移植自 CodeBuddy agents-md-check（UserPromptSubmit → Cursor sessionStart）。
# 失败一律 exit 0 + 合法 JSON，fail-open。

set +e
INPUT="$(cat)"

ROOT=""
if command -v python3 >/dev/null 2>&1; then
  ROOT="$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
  d=json.load(sys.stdin)
  r=d.get("workspace_roots") or []
  print(r[0] if r else "")
except Exception:
  print("")' 2>/dev/null)"
fi
[ -n "$ROOT" ] || ROOT="${PWD}"

FOUND=""
[ -f "$ROOT/AGENTS.md" ] && FOUND="AGENTS.md"
if ls "$ROOT"/.cursor/rules/*.mdc >/dev/null 2>&1; then
  FOUND="${FOUND:+$FOUND + }.cursor/rules/*.mdc"
fi

OPTIONAL=""
if ls "$ROOT"/docs/*.md >/dev/null 2>&1; then
  OPTIONAL="docs/"
fi
if [ -d "$ROOT/specs" ]; then
  OPTIONAL="${OPTIONAL:+$OPTIONAL + }specs/"
fi
if ls "$ROOT"/.cursor/skills/*/SKILL.md >/dev/null 2>&1; then
  OPTIONAL="${OPTIONAL:+$OPTIONAL + }.cursor/skills/"
fi

if [ -z "$FOUND" ] && [ -z "$OPTIONAL" ]; then
  printf '%s\n' '{}'
  exit 0
fi

CTX="[agents-md-check] Project has conventions: ${FOUND:-none}${FOUND:+; optional: ${OPTIONAL}}. MUST read AGENTS.md and apply .cursor/rules before starting work. Pipeline: .cursor/rules/execution-discipline.mdc. Do not skip."

if command -v python3 >/dev/null 2>&1; then
  CTX="$CTX" python3 -c 'import json,os; print(json.dumps({"additional_context": os.environ["CTX"]}, ensure_ascii=False))'
else
  # 极简兜底：无 python3 时尽量输出合法 JSON（上下文中的引号已规避）
  printf '{"additional_context":"%s"}\n' "$CTX"
fi
exit 0
