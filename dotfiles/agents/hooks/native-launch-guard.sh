#!/usr/bin/env bash
# PreToolUse(Bash) guard: refuses a command that starts a Wine/Proton game
# client (wine, wine64, proton, steam-run, umu-run or a Windows .exe) outside a
# machine-capacity native session. An unwrapped client lands in the caller's
# terminal scope, where capacity admission neither counts its GPU use nor caps
# it. Self-wrapping routes (`wisp lan pool`, wisp online launch.sh) pass.
#
# Kill-switch: `north config agents off native-launch-guard` or env
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
  *wine*|*proton*|*steam-run*|*umu-run*|*.exe*|*.EXE*) ;;
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

def wrapped(words):
    for index, word in enumerate(words):
        if re.search(r"machine-capacity(\.mjs)?$", word) and "session" in words[index + 1:]:
            rest = words[index + 1:]
            if "--class=native" in rest or any(a == "--class" and b == "native" for a, b in zip(rest, rest[1:])):
                return True
    return False

if wrapped(tokens):
    allow()

PREFIXES = {"env", "exec", "command", "nohup", "setsid", "nice", "ionice", "sudo", "doas", "stdbuf", "timeout", "dbus-run-session", "time", "gamemoderun"}
LAUNCHERS = {"wine", "wine64", "proton", "steam-run", "umu-run"}

def launches(words):
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
        helper = [w for w in words[index:index + 2] if w.endswith("machine-capacity.mjs")]
        if helper and "--" in words[index:]:
            return launches(words[words.index("--", index) + 1:])
        return name in LAUNCHERS or name.lower().endswith(".exe")
    return False

segment = []
for token in tokens + [";"]:
    if token and set(token) <= set(";&|()\n"):
        if launches(segment):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    "No. A Wine/Proton/Warcraft client started here runs in your terminal scope, outside "
                    "capacity admission, and can saturate the GPU. Wrap it: bun \"$(dirname \"$(agents path "
                    "machine-capacity)\")/scripts/machine-capacity.mjs\" session --class native --owner OWNER "
                    "-- COMMAND ARG... (one session per client; retry DEFER after 30 s). Self-wrapping routes: "
                    "`wisp lan pool`, ~/.local/share/wisp/online/launch.sh."
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
