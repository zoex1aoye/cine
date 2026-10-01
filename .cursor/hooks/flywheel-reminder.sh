#!/usr/bin/env bash
# beforeSubmitPrompt hook：用户消息含长期口径信号时提醒（规范飞轮）。
# 移植自 CodeBuddy flywheel-reminder.sh。
#
# Cursor 限制：beforeSubmitPrompt 仅支持 continue / user_message，不能注入 agent 上下文。
# Agent 侧飞轮纪律以 alwaysApply 的 .cursor/rules/flywheel.mdc 为准；
# 本 hook 在命中信号词时用 user_message 提示用户（不阻断提交）。
# 失败一律 continue:true，fail-open。

set +e
INPUT="$(cat)"

PROMPT=""
if command -v python3 >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
  print(json.load(sys.stdin).get("prompt") or "")
except Exception:
  print("")' 2>/dev/null)"
else
  PROMPT="$INPUT"
fi

if [ -z "$PROMPT" ]; then
  printf '%s\n' '{"continue":true}'
  exit 0
fi

if printf '%s' "$PROMPT" | grep -qE '以后都|今后|以后每次|每次都|都要|记住|记一下|统一|约定|口径|规范|长期有效|永久生效'; then
  MSG='[flywheel] 本条含长期性要求/口径信号。若需长期遵守，请确认是否写回 .cursor/rules、AGENTS.md 或 .cursor/skills；若仅本次任务，可忽略。Agent 侧见 flywheel.mdc。'
  if command -v python3 >/dev/null 2>&1; then
    MSG="$MSG" python3 -c 'import json,os; print(json.dumps({"continue": True, "user_message": os.environ["MSG"]}, ensure_ascii=False))'
  else
    printf '{"continue":true,"user_message":"%s"}\n' "$MSG"
  fi
  exit 0
fi

printf '%s\n' '{"continue":true}'
exit 0
