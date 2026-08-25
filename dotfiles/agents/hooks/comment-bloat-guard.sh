#!/usr/bin/env bash
# PreToolUse ADVISORY guard — comment-bloat, machine bootstrap comment conventions.
# A comment states a constraint
# the code cannot say; default one line; narrative (how a bug was found,
# observed outputs/timings, dates, incident references) belongs in the commit
# message, not the file. This guard flags likely narrative/bloat at write
# time — it NEVER denies. Same env kill-switch as the other authoring hooks
# (AGENT_NO_AUTHORING_HOOKS).
#
# Scope: only ADDED text (tool_input.new_string for Edit, .content for Write,
# each edits[].new_string for MultiEdit) — an unrelated pre-existing bloated
# comment in the same file must never trigger on an edit that didn't add it.
# Carve-outs: .md/.json/.tsv/.lock files skip entirely (prose/data, not code);
# a line containing SPDX, Copyright, or GENERATED is exempt (license/tooling
# headers, not narrative).
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

# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

# python3 does the JSON I/O used by the hook protocol.
# Source goes in a variable and runs via `python3 -c "$PY"`, never a heredoc,
# so stdin stays free for the hook's own JSON envelope.
read -r -d '' PY <<'PYEOF' || true
import sys, json, os, re

def allow():
    # No opinion -> allow, silently. Empty stdout, exit 0.
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    allow()

if data.get("tool_name") not in ("Edit", "Write", "MultiEdit"):
    allow()

tool_input = data.get("tool_input", {}) or {}
file_path = tool_input.get("file_path", "") or ""
if not file_path:
    allow()

_, ext = os.path.splitext(file_path)
if ext.lower() in (".md", ".json", ".tsv", ".lock"):
    allow()

# Gather only the ADDED text for each tool shape.
added_chunks = []
if "new_string" in tool_input:
    added_chunks.append(tool_input.get("new_string", "") or "")
elif "content" in tool_input:
    added_chunks.append(tool_input.get("content", "") or "")
elif isinstance(tool_input.get("edits"), list):
    for edit in tool_input["edits"]:
        if isinstance(edit, dict):
            added_chunks.append(edit.get("new_string", "") or "")

if not added_chunks:
    allow()

COMMENT_PREFIXES = ("//", "#", ";;", "--", "/*", "*")
EXEMPT_RE = re.compile(r"SPDX|Copyright|GENERATED")
ROT_RES = [
    re.compile(r"20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]"),
    re.compile(r"\bObserved\b"),
    re.compile(r"[0-9]+ms"),
]

def is_comment_line(line):
    s = line.strip()
    return any(s.startswith(p) for p in COMMENT_PREFIXES)

worst_run = 0
rot_hit = False
for chunk in added_chunks:
    run = 0
    for raw_line in chunk.splitlines():
        if not is_comment_line(raw_line):
            run = 0
            continue
        if EXEMPT_RE.search(raw_line):
            # Exempt lines don't extend a run and don't themselves trigger rot,
            # but they also don't reset one already in progress mid-header.
            continue
        run += 1
        worst_run = max(worst_run, run)
        for rx in ROT_RES:
            if rx.search(raw_line):
                rot_hit = True

if worst_run <= 3 and not rot_hit:
    allow()

if rot_hit and worst_run <= 3:
    worst_run = max(worst_run, 1)

reason = (
    "comment-bloat: %d-line comment block added — constitution comment "
    "conventions: constraint only, default one line; narrative goes in the "
    "commit message." % worst_run
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "additionalContext": reason,
    }
}))
sys.exit(0)
PYEOF

printf '%s' "$payload" | python3 -c "$PY"
