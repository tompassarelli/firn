#!/usr/bin/env bash
# Codex behavior guard: UserPromptSubmit, PreToolUse, PostToolUse and Stop.
# ============================================================================
# Turns the Codex overlay's worst recorded failures into checks Codex can't
# skip, and shows it a score of issues closed instead of claims defended.
# Decisions live in lib/codex_behavior.py; a missing interpreter or malformed
# input allows.
#
# Kill-switch: persistent `north config agents off codex-behavior-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but 0/false). Shared impl:
# lib/authoring-killswitch.sh.
# ============================================================================
set -uo pipefail

payload="$(head -c 1048576)"

# Bound to every tool; only shell commands and plan updates need a decision,
# so every other tool call exits before paying for an interpreter.
case "$payload" in
  *'"hook_event_name":"PreToolUse"'*|*'"hook_event_name": "PreToolUse"'*|\
  *'"hook_event_name":"PostToolUse"'*|*'"hook_event_name": "PostToolUse"'*)
    case "$payload" in
      *'"tool_name":"Bash"'*|*'"tool_name": "Bash"'*|\
      *'"tool_name":"update_plan"'*|*'"tool_name": "update_plan"'*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

decider="$(dirname "$0")/lib/codex_behavior.py"
python_bin="${NORTH_AGENT_PYTHON:-python3}"
command -v -- "$python_bin" >/dev/null 2>&1 && [ -r "$decider" ] || exit 0
printf '%s' "$payload" | "$python_bin" "$decider" 2>/dev/null
exit 0
