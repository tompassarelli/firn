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
# This hook fires after an edit to a .rkt (or Beagle dialect) file and emits
# actionable guidance on stderr (exit 2 -> surfaced to the agent) so the NEXT
# build/test uses the pinned racket and fresh bytecode. It never blocks the edit
# (the edit already happened); it makes the failure mode impossible to miss.
#
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 -> no-op (parity with the other hooks).
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

payload="$(cat 2>/dev/null || true)"
# file_path from the tool input (best-effort, no jq dependency).
file="$(printf '%s' "$payload" | sed -nE 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
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

printf '%s' "$msgs" >&2
exit 2
