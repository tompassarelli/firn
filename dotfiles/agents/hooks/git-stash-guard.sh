#!/usr/bin/env bash
# PreToolUse guard — refuses unsafe use of git's stash: bare `git stash`,
# `git stash push`/`save` without `-m`, and `git stash pop`. The stash stack is
# shared by every worktree of a repository, so an unnamed push or a pop can take
# another session's changes. Quoted segments and heredoc bodies are stripped
# before matching, and only command-position invocations count.
#
# Kill-switch: persistent `north config agents off git-stash-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but
# 0/false; 0/false forces guards live). Shared impl: lib/authoring-killswitch.sh.
# ============================================================================
set -uo pipefail

# Drain before every decision, including the kill-switch. Keep active-path input
# memory-bounded; an oversized envelope follows the existing malformed fail-open.
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

# Kill-switch: shared semantics in lib/authoring-killswitch.sh — persistent
# `north config agents off git-stash-guard` (live) or env AGENT_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

# Fast-path: this hook only has an opinion on Bash commands mentioning `git`.
case "$payload" in
  *git*) ;;
  *) exit 0 ;;
esac

read -r -d '' PY <<'PYEOF' || true
import sys, json, re

def allow():
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    allow()

if data.get("tool_name", "") != "Bash":
    allow()

cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
if not cmd:
    allow()

# --- Strip heredoc bodies, then quoted segments, so a COMMIT MESSAGE or a
# heredoc body that merely mentions the trigger phrase is never treated as an
# invocation. Blanking (not deleting) preserves newline structure so the
# command-position anchors below still line up. ---

_HEREDOC_START = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")

def _blank(text):
    return "".join(c if c == "\n" else " " for c in text)

def strip_heredocs(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        m = _HEREDOC_START.search(s, i)
        if not m:
            out.append(s[i:])
            break
        out.append(s[i:m.end()])
        line_end = s.find("\n", m.end())
        if line_end == -1:
            out.append(s[m.end():])
            break
        out.append(s[m.end():line_end + 1])
        body_start = line_end + 1
        delim = m.group(2)
        term = re.compile(r"^[ \t]*" + re.escape(delim) + r"[ \t]*$", re.M)
        tm = term.search(s, body_start)
        if tm:
            out.append(_blank(s[body_start:tm.start()]))
            i = tm.start()
        else:
            # Unterminated heredoc: blank the remainder rather than matching
            # a body that never actually became a live command.
            out.append(_blank(s[body_start:]))
            i = n
    return "".join(out)

def strip_quotes(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == "'":
            j = s.find("'", i + 1)
            end = n if j == -1 else j + 1
            out.append(_blank(s[i:end]))
            i = end
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\" and j + 1 < n:
                    j += 2
                    continue
                if s[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(_blank(s[i:j]))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)

cleaned = strip_quotes(strip_heredocs(cmd))

SEP = r"(?:^|[\n;&|({`])"
WRAP = r"(?:sudo\s+|doas\s+)?"
ARG_SPAN = r"[^\n;&|)}`]*"

# `git [-C dir] stash ARGS` at command position.
STASH_RE = re.compile(SEP + r"\s*" + WRAP + r"git(?:\s+-C\s+\S+)*\s+stash\b(" + ARG_SPAN + r")")

def stash_is_unsafe(args_text):
    tokens = args_text.split()
    if not tokens:
        return True
    sub = tokens[0]
    if sub == "pop":
        return True
    if sub in ("push", "save") or sub.startswith("-"):
        rest = tokens[1:] if sub in ("push", "save") else tokens
        for t in rest:
            if t in ("-m", "--message") or t.startswith("--message=") or (t.startswith("-m") and len(t) > 2):
                return False
            if re.match(r"^-[A-Za-z]+$", t) and t.endswith("m"):
                return False
        return True
    return False

hit = any(stash_is_unsafe(m.group(1)) for m in STASH_RE.finditer(cleaned))
if not hit:
    allow()

reason = (
    "No. The stash is shared by every worktree, so another session can pop "
    "your changes. Commit a WIP commit instead (git commit -m wip PATHS), or "
    "`git stash push -u -m TAG` then `git stash apply <sha>`."
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

printf '%s' "$payload" | python3 -c "$PY"
