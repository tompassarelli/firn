#!/usr/bin/env bash
# PreToolUse(Bash) guard for Claude Code workers (agent_type worker*): refuses a
# foreground command that can block past 60 seconds (waits, sleeps, safe-push,
# leased runs, suites, farm runs, timeouts over 60 s). Messages reach a worker
# only between tool calls, so long work runs with run_in_background and the
# lead's messages arrive at once.
#
# Kill-switch: `north config agents off worker-wait-guard` or env
# AGENT_NO_AUTHORING_HOOKS (shared impl: lib/authoring-killswitch.sh).
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

case "$payload" in
  *'"agent_type"'*'"worker'*) ;;
  *) exit 0 ;;
esac
[ "$payload_oversized" -eq 0 ] || exit 0

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

read -r -d '' PY <<'PYEOF' || true
import json, re, sys

LIMIT_S = 60

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if not isinstance(data, dict) or data.get("tool_name") != "Bash":
    sys.exit(0)
agent_type = data.get("agent_type")
if not (isinstance(agent_type, str) and agent_type.startswith("worker")):
    sys.exit(0)
tool_input = data.get("tool_input") or {}
if not isinstance(tool_input, dict) or tool_input.get("run_in_background") is True:
    sys.exit(0)
command = tool_input.get("command")
if not isinstance(command, str):
    sys.exit(0)

INERT_HEREDOC = re.compile(r"<<(-?)[ \t]*(['\"]?)([A-Za-z_][\w.-]*)\2")
CMD_START = r"(?:^|[;&|(\n`])\s*(?:(?:[A-Za-z_]\w*=\S*|timeout\s+[\d.]+[smhd]?|env|nice|nohup|exec)\s+)*"


def strip_inert(text):
    out, pending, i, n = [], [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            out.append(text[i:i + 2])
            i += 2
        elif c == "'":
            j = text.find("'", i + 1)
            out.append("''")
            i = n if j < 0 else j + 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append('""')
            i = j + 1
        elif c == "<" and INERT_HEREDOC.match(text, i) and not text.startswith("<<<", i):
            m = INERT_HEREDOC.match(text, i)
            pending.append((m.group(3), m.group(1) == "-"))
            out.append(m.group(0))
            i = m.end()
        elif c == "\n" and pending:
            out.append("\n")
            i += 1
            for delim, tabs in pending:
                while i < n:
                    eol = text.find("\n", i)
                    eol = n if eol < 0 else eol
                    line = text[i:eol]
                    i = eol + 1
                    if (line.lstrip("\t") if tabs else line) == delim:
                        break
            pending = []
        else:
            out.append(c)
            i += 1
    return "".join(out)


reason = None
timeout = tool_input.get("timeout")
if isinstance(timeout, (int, float)) and timeout > LIMIT_S * 1000:
    reason = f"a timeout of {int(timeout // 1000)} s"
else:
    inert = strip_inert(command)
    patterns = [
        (r"\buntil\b[\s\S]*\bsleep\b", "an until/sleep wait loop", command),
        (r"\bwhile\b[\s\S]*\bsleep\b", "a while/sleep wait loop", command),
        (CMD_START + r"(?:\S*/)?safe-push\b", "safe-push", inert),
        (CMD_START + r"(?:gh\s+run\s+watch\b|gh\s+pr\s+checks\b[^\n]*--watch)", "a CI watch", inert),
        (CMD_START + r"(?:bun\s+(?:\S*/)?|\S*/)?machine-capacity\.mjs\s+(?:run|session)\b", "a leased run", inert),
        (r"\bbun\s+(run\s+)?test\b(?!\s+\S+\.test\.ts)", "a test suite", command),
        (CMD_START + r"bun\s+wisp\s+farm\b", "a farm run", inert),
    ]
    for pattern, label, text in patterns:
        if re.search(pattern, text):
            reason = label
            break
    if reason is None:
        for m in re.finditer(r"\b(?:sleep|timeout)\s+(\d+)", command):
            if int(m.group(1)) > LIMIT_S:
                reason = f"`{m.group(0)}`"
                break
if reason is None:
    sys.exit(0)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Workers never block in the foreground on {reason}: the lead's messages "
            "reach you only between tool calls and must arrive at once. Rerun it with "
            "run_in_background: true and wait for its completion notification or a "
            "Monitor event, checking messages in between."
        ),
    }
}))
PYEOF

printf '%s' "$payload" | "${NORTH_AGENT_PYTHON:-python3}" -c "$PY"
exit 0
