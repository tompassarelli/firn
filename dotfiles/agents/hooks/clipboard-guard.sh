#!/usr/bin/env bash
# PreToolUse guard — refuses agent writes to Tom's clipboard: `wl-copy` (including
# --clear) and niri's screenshot actions, which always replace the clipboard.
# A write between Tom's Print and his paste replaces his screenshot. Quoted
# segments and heredoc bodies are stripped; only command-position invocations count.
#
# Kill-switch: persistent `north config agents off clipboard-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but 0/false). Shared impl: lib/authoring-killswitch.sh.
set -uo pipefail

capture_hook_stdin() {
  local chunk status keep
  local LC_ALL=C
  payload=""
  payload_oversized=0
  while :; do
    chunk=""
    IFS= read -r -N 65536 chunk
    status=$?
    if [ -n "$chunk" ]; then
      keep=$((1048576 - ${#payload}))
      [ "$keep" -le 0 ] || payload+="${chunk:0:$keep}"
      [ "${#chunk}" -le "$keep" ] || payload_oversized=1
    fi
    [ "$status" -eq 0 ] || break
  done
}
capture_hook_stdin

[ "$payload_oversized" -eq 0 ] || exit 0

case "$payload" in
  *wl-copy*|*screenshot*) ;;
  *) exit 0 ;;
esac

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type hook_decide >/dev/null 2>&1 || exit 0
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

read -r -d '' PY <<'PYEOF' || true
import sys, json, re
sys.path.insert(0, sys.argv[1])
from shellcmd import strip_heredocs, strip_quotes

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(65)

if data.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
if not cmd:
    sys.exit(0)

cleaned = strip_quotes(strip_heredocs(cmd))

SEP = r"(?:^|[\n;&|({`]|\$\()"
WRAP = r"(?:(?:sudo|doas|env|command|exec|nohup|timeout\s+\S+|run-bounded\s+\S+\s+--)\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
PATHED = r"(?:\S*/)?"

WL_COPY = re.compile(SEP + r"\s*" + WRAP + PATHED + r"wl-copy\b")
NIRI_SHOT = re.compile(SEP + r"\s*" + WRAP + PATHED + r"niri\s+msg\b[^\n;&|)}`]*?\baction\s+screenshot(?:-screen|-window)?\b")

if not (WL_COPY.search(cleaned) or NIRI_SHOT.search(cleaned)):
    sys.exit(0)

reason = (
    "No. Agents never write or clear Tom's clipboard: wl-copy and niri screenshot "
    "actions replace the screenshot he is about to paste. Capture with "
    "`agent-capture --screen OUT.png` (or --region \"X,Y WxH\" OUT.png, or "
    "--window ID OUT.png for a visible floating window) and pass the file path."
)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
sys.exit(0)
PYEOF

hook_decide python3 -c "$PY" "$(dirname "$0")/lib"
