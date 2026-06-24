#!/usr/bin/env bash
# Toggle the fleet-protocol guard via a sentinel file it checks.
# Driven by the /fleet-guard slash command. Usage: [on|off|status]  (default: status)
#   off  -> create sentinel  -> raw Agent/Workflow ALLOWED (guard bypassed)
#   on   -> remove sentinel  -> raw Agent/Workflow BLOCKED  (guard active)
set -uo pipefail

sentinel="$HOME/.claude/fleet-guard.off"

case "${1:-status}" in
  off | disable | bypass)
    touch "$sentinel"
    echo "fleet guard OFF — raw Agent/Workflow now ALLOWED (sentinel: $sentinel)"
    ;;
  on | enable)
    rm -f "$sentinel"
    echo "fleet guard ON — raw Agent/Workflow BLOCKED"
    ;;
  status | "")
    if [ -f "$sentinel" ]; then
      echo "fleet guard: OFF (Agent/Workflow allowed). Run: /fleet-guard on  to re-enable."
    else
      echo "fleet guard: ON (Agent/Workflow blocked). Run: /fleet-guard off  to bypass."
    fi
    ;;
  *)
    echo "usage: /fleet-guard [on|off|status]"
    ;;
esac
