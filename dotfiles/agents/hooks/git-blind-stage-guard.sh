#!/usr/bin/env bash
# PreToolUse guard — refuses BLIND git staging: `git add -A`, `git add -u`,
# `git add .`, and `git commit -a` (incl. `-am`-style short clusters).
# ============================================================================
# Enumerating paths (`git add path/to/file`) forces the agent to know the
# diff before it lands; blind staging sweeps in whatever else is dirty in the
# tree — including another agent's in-flight WIP or an unreviewed cherry-pick.
#
# THE FALSE-POSITIVE TRAP (why this needs care, not just a substring grep):
# naive substring matching would deny a commit whose MESSAGE mentions the
# phrase "git add -A" (a corrective commit that literally says that) or a
# heredoc commit body that quotes the phrase for documentation. Denying those
# would be wrong and maddening — a guard that blocks legitimate commits is
# worse than the disease it treats. So this guard strips quoted segments and
# heredoc bodies BEFORE matching, then anchors at COMMAND POSITION (start of
# string, after a shell separator, or after sudo/doas) — never a bare
# occurrence anywhere in the string.
#
# Kill-switch: persistent `north config agents off git-blind-stage-guard` OR env
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
# `north config agents off git-blind-stage-guard` (live) or env AGENT_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
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

ADD_RE = re.compile(SEP + r"\s*" + WRAP + r"git\s+add\b(" + ARG_SPAN + r")")
COMMIT_RE = re.compile(SEP + r"\s*" + WRAP + r"git\s+commit\b(" + ARG_SPAN + r")")

# A pure short-option cluster: single dash, letters only (never `--long`, so
# `--all`/`--amend`/`--author` etc. are handled by their own exact checks,
# never by an incidental 'a' inside a long option name).
SHORT_CLUSTER = re.compile(r"^-[A-Za-z]+$")

def add_is_blind(args_text):
    tokens = args_text.split()
    for t in tokens:
        if t in ("-A", "--all", "-u", "--update", "--no-ignore-removal"):
            return True
        if t == ".":
            return True
        if SHORT_CLUSTER.match(t) and ("A" in t[1:] or "u" in t[1:]):
            return True
    return False

def commit_is_blind(args_text):
    tokens = args_text.split()
    for t in tokens:
        if t in ("-a", "--all"):
            return True
        if SHORT_CLUSTER.match(t) and "a" in t[1:].lower():
            return True
    return False

hit = None
for m in ADD_RE.finditer(cleaned):
    if add_is_blind(m.group(1)):
        hit = "git add"
        break
if hit is None:
    for m in COMMIT_RE.finditer(cleaned):
        if commit_is_blind(m.group(1)):
            hit = "git commit -a"
            break

if hit is None:
    allow()

reason = (
    "BLOCKED: blind staging refused (%s) — enumerate the paths you intend to "
    "commit instead, e.g. `git add path/to/file` or `git commit path/to/file "
    "-m '...'`. A commit MESSAGE or heredoc body that merely mentions "
    "the phrase is unaffected — only a real command-position invocation is "
    "denied. Rare explicit override: `north config agents off git-blind-stage-guard` (persistent, "
    "live), or a session LAUNCHED with AGENT_NO_AUTHORING_HOOKS=1."
) % hit

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
