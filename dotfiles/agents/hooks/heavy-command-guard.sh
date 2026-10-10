#!/usr/bin/env bash
# PreToolUse(Bash) guard: refuses a heavy build, full test suite or headless
# render started outside `machine-capacity run`. Unleased work lands in the
# caller's terminal scope, where admission neither counts nor caps it.
#
# Kill-switch: `north config agents off heavy-command-guard` or env
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
  *cargo*|*bun*) ;;
  *) exit 0 ;;
esac

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

read -r -d '' PY <<'PYEOF' || true
import json, os, re, shlex, sys

def allow():
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(65)
if data.get("tool_name", "") != "Bash":
    allow()
cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
if not cmd:
    allow()

HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)^[ \t]*\2[ \t]*$", re.S | re.M)
text = HEREDOC.sub(lambda m: m.group(0)[: m.start(3) - m.start(0)] + m.group(2), cmd)

try:
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = "#"
    tokens = list(lexer)
except ValueError:
    allow()

PREFIXES = {"env", "exec", "command", "nohup", "setsid", "nice", "ionice", "stdbuf", "timeout", "time"}

def heavy(words):
    index = 0
    while index < len(words):
        word = words[index]
        name = os.path.basename(word)
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", word) or word == "--" or (word.startswith("-") and index > 0):
            index += 1
            continue
        if name in PREFIXES:
            index += 1
            if name == "timeout" and index < len(words) and re.match(r"^[0-9.]+[smhd]?$", words[index]):
                index += 1
            continue
        break
    rest = words[index:]
    if not rest:
        return None
    if any(re.search(r"machine-capacity(\.mjs)?$", w) for w in rest[:3]):
        return None
    name = os.path.basename(rest[0])
    args = rest[1:]
    plain = [a for a in args if not a.startswith("-")]
    if name == "cargo" and plain[:1] == ["build"]:
        return "cargo build"
    if name == "bun":
        if plain[:1] == ["test"] and not any("/" in a or a.endswith((".ts", ".js", ".tsx")) for a in plain[1:]):
            return "bun test (full suite)"
        if plain[:1] == ["wisp"] or (plain[:2] == ["run", "wisp"]):
            sub = plain[1:] if plain[0] == "wisp" else plain[2:]
            if sub[:2] == ["map", "build"]:
                return "wisp map build"
            if sub[:1] == ["view"] or (sub[:1] == ["headless"] and "--render" in args):
                return "wisp render"
    return None

segment = []
for token in tokens + [";"]:
    if token and set(token) <= set(";&|()\n"):
        found = heavy(segment)
        if found:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"No. `{found}` is heavy and would run in your terminal scope, outside capacity admission. "
                    "Run it as: bun \"$(dirname \"$(agents path machine-capacity)\")/scripts/machine-capacity.mjs\" "
                    "run --owner OWNER --timeout-seconds N -- COMMAND ARG... (omit --class to size from measured "
                    "use; --class gpu for headless renders). Single test files and cargo check pass unwrapped."
                ),
            }}))
            sys.exit(0)
        segment = []
    else:
        segment.append(token)
allow()
PYEOF

python_bin="${NORTH_AGENT_PYTHON:-python3}"
hook_decide "$python_bin" -c "$PY"
exit 0
