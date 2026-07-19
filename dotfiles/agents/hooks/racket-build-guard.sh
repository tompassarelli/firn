#!/usr/bin/env bash
# PostToolUse guard (Edit|Write|MultiEdit) — the DETERMINISTIC layer that stops
# the two recurring Racket pains in Beagle/Racket projects:
#
#   1. VERSION MISMATCH — the system racket (nixos-config) and a project's
#      flake-pinned racket differ (e.g. 9.2 vs 9.1). Bytecode (.zo) is
#      version-specific: load 9.1-compiled .zo under 9.2 and racket dies with
#      "body of .../raco.rkt". Worktrees are the classic trap — no .direnv, so
#      bare `racket`/`raco` = the system version, not the pin.
#   2. STALE BYTECODE — a .rkt edited but its compiled/<name>_rkt.zo not rebuilt,
#      so a later run executes old code and a bug looks unfixable / confounded.
#
# This hook fires after an edit to a .rkt file and returns actionable guidance
# through PostToolUse additionalContext so the NEXT build/test uses the pinned
# racket and fresh bytecode. It always exits 0: the edit already happened, and
# diagnostics are context rather than a false hook failure.
#
# Kill-switch: persistent `north config guards off` (state) OR env
# CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces guards live).
# Shared impl: lib/authoring-killswitch.sh. Parity with the other hooks.
set -uo pipefail
umask 077

# Stay well inside the provider's 15s hook deadline. The inner process owns
# project discovery, pin sourcing, version probes, and JSON encoding; this
# supervisor buffers and validates its complete envelope. A slow pin script or
# filesystem becomes a clean no-op, never a provider timeout or partial JSON.
if [ "${RACKET_BUILD_GUARD_INNER:-0}" != 1 ]; then
  json_payload="$(RACKET_BUILD_GUARD_INNER=1 \
    timeout --signal=TERM --kill-after=0.2s 4s "$0" 2>/dev/null || true)"
  if [ -n "$json_payload" ] &&
      printf '%s' "$json_payload" | timeout --signal=TERM --kill-after=0.1s 0.5s \
      python3 -c '
import json
import sys

payload = json.load(sys.stdin)
assert payload.get("hookSpecificOutput", {}).get("hookEventName") == "PostToolUse"
' 2>/dev/null; then
    printf '%s\n' "$json_payload"
  fi
  exit 0
fi

# Kill-switch: shared semantics in lib/authoring-killswitch.sh — persistent
# `north config guards off` (state, live) or env CLAUDE_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

payload="$(cat 2>/dev/null || true)"
# Resolve either the ordinary provider file_path or Codex canonical apply_patch
# target headers. Patch body text is never considered a target, so a comment
# mentioning a .rkt path cannot trigger diagnostics.
file="$(
  printf '%s' "$payload" | python3 -c '
import json
import os
import re
import sys

try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        raise ValueError("root")
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    cwd = data.get("cwd", "") or os.getcwd()
    if not isinstance(tool, str) or not isinstance(tool_input, dict):
        raise ValueError("envelope")
    if not isinstance(cwd, str) or not cwd or "\0" in cwd:
        raise ValueError("cwd")
    targets = []
    direct = tool_input.get("file_path")
    if isinstance(direct, str) and direct:
        targets.append(direct)
    if tool.rsplit(".", 1)[-1] == "apply_patch":
        patch = tool_input.get("command")
        if not isinstance(patch, str) or "*** Begin Patch" not in patch:
            raise ValueError("patch")
        targets.extend(re.findall(
            r"^\*\*\* (?:Add|Update|Delete) File:\s+(.+?)\s*$",
            patch, re.M))
        targets.extend(re.findall(
            r"^\*\*\* Move to:\s+(.+?)\s*$", patch, re.M))
    for target in targets:
        if not isinstance(target, str) or not target or any(
                char in target for char in ("\0", "\n", "\r")):
            raise ValueError("target")
        expanded = os.path.expanduser(target)
        if not os.path.isabs(expanded):
            expanded = os.path.join(cwd, expanded)
        canonical = os.path.realpath(os.path.abspath(expanded))
        if canonical.endswith(".rkt"):
            print(canonical)
            raise SystemExit(0)
except Exception:
    pass
' 2>/dev/null
)"
[ -n "$file" ] || exit 0

# Only racket-compiled sources (these go through .zo bytecode).
case "$file" in
  *.rkt) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Nearest ancestor that is a Racket/Beagle PROJECT root. Markers, in order: the
# racket-pin script (authoritative) or a flake. NOT info.rkt — every Racket
# collection has one, so it would stop at a sub-collection (e.g. beagle-lib/)
# and miss the project's bin/_beagle-racket one level up.
dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || exit 0
root="" ; d="$dir"
while [ "$d" != "/" ] && [ -n "$d" ]; do
  if [ -f "$d/bin/_beagle-racket" ] || [ -f "$d/flake.nix" ]; then root="$d"; break; fi
  d="$(dirname "$d")"
done
[ -n "$root" ] || exit 0

msgs=""

# --- (1) version mismatch: ambient `racket` vs the project's pinned racket -----
ambient="$(command -v racket 2>/dev/null || true)"
ambient_ver=""
[ -n "$ambient" ] && ambient_ver="$("$ambient" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | head -1)"

pin_path="" ; pin_ver=""
if [ -f "$root/bin/_beagle-racket" ]; then
  # Source in a subshell so we read the resolved pin without polluting this env.
  # shellcheck disable=SC1091
  pin_path="$(cd "$root" 2>/dev/null && source "$root/bin/_beagle-racket" >/dev/null 2>&1 && command -v "${RACKET:-racket}" 2>/dev/null || true)"
  [ -n "$pin_path" ] && pin_ver="$("$pin_path" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | head -1)"
fi

if [ -n "$pin_ver" ] && [ -n "$ambient_ver" ] && [ "$pin_ver" != "$ambient_ver" ]; then
  msgs="${msgs}⚠ Racket version mismatch: ambient \`racket\` is ${ambient_ver}, but ${root##*/} pins ${pin_ver}.
   .zo bytecode is version-specific — bare racket/raco here will mis-load it (\"body of raco.rkt\").
   For EVERY build/test in this project: \`source bin/_beagle-racket\` then use \$RACKET / \$RACO
   (or \`direnv exec . raco …\`). Never bare racket/raco. In a worktree, _beagle-racket falls back
   to the canonical checkout's pin — source it, don't call bare.
"
fi

# --- (2) stale bytecode for the edited file -----------------------------------
zo="$dir/compiled/$(basename "$file" .rkt)_rkt.zo"
if [ -f "$zo" ] && [ "$file" -nt "$zo" ]; then
  msgs="${msgs}⚠ Stale bytecode: $(basename "$file") is newer than its compiled .zo.
   Rebuild before testing or the old code runs and bugs look unfixable:
     (cd ${root} && source bin/_beagle-racket && \"\$RACO\" make ${file#"$root"/})
"
fi

[ -z "$msgs" ] && exit 0

json_payload="$(python3 -c '
import json
import sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": sys.argv[1],
    }
}))
' "$msgs" 2>/dev/null)" || json_payload=""
if [ -n "$json_payload" ]; then
  printf '%s\n' "$json_payload"
else
  # Transport failure must not turn an advisory PostToolUse hook into a generic
  # hook error. Preserve the diagnostic as a plain fallback and still exit 0.
  printf '%s' "$msgs" >&2
fi
exit 0
