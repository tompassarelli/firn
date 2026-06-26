#!/usr/bin/env bash
# Toggle the fleet-redirect via a sentinel file it checks.
# Driven by the /fleet-redirect slash command. Usage: [on|off|status]  (default: status)
#   off  -> create sentinel  -> raw Agent/Workflow ALLOWED (redirect bypassed)
#   on   -> remove sentinel  -> raw Agent/Workflow REDIRECTED to the fleet
set -uo pipefail

sentinel="$HOME/.claude/fleet-redirect.off"

case "${1:-status}" in
  off | disable | bypass)
    touch "$sentinel"
    echo "fleet redirect OFF — raw Agent/Workflow now ALLOWED (sentinel: $sentinel)"
    ;;
  on | enable)
    rm -f "$sentinel"
    echo "fleet redirect ON — raw Agent/Workflow REDIRECTED to the fleet"
    ;;
  status | "")
    if [ -f "$sentinel" ]; then
      echo "fleet redirect: OFF (Agent/Workflow allowed). Run: /fleet-redirect on  to re-enable."
    else
      echo "fleet redirect: ON (Agent/Workflow redirected to fleet). Run: /fleet-redirect off  to bypass."
    fi
    ;;
  *)
    echo "usage: /fleet-redirect [on|off|status]"
    ;;
esac
