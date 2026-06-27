#!/usr/bin/env bash
# Toggle the agent-redirect via a sentinel file it checks.
# Driven by the /agent-redirect slash command. Usage: [on|off|status]  (default: status)
#   off  -> create sentinel  -> raw Agent/Workflow ALLOWED (redirect bypassed)
#   on   -> remove sentinel  -> raw Agent/Workflow REDIRECTED to lodestar agents
set -uo pipefail

sentinel="$HOME/.claude/agent-redirect.off"

case "${1:-status}" in
  off | disable | bypass)
    touch "$sentinel"
    echo "agent redirect OFF — raw Agent/Workflow now ALLOWED (sentinel: $sentinel)"
    ;;
  on | enable)
    rm -f "$sentinel"
    echo "agent redirect ON — raw Agent/Workflow REDIRECTED to lodestar agents"
    ;;
  status | "")
    if [ -f "$sentinel" ]; then
      echo "agent redirect: OFF (Agent/Workflow allowed). Run: /agent-redirect on  to re-enable."
    else
      echo "agent redirect: ON (Agent/Workflow redirected to lodestar). Run: /agent-redirect off  to bypass."
    fi
    ;;
  *)
    echo "usage: /agent-redirect [on|off|status]"
    ;;
esac
