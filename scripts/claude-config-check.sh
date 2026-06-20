#!/usr/bin/env bash
# claude-config-check.sh — anti-rot validator for the Claude global config surface.
# ============================================================================
# The Claude config (settings.json + hooks + skills + CLAUDE.md) injects behavior
# into every agent session, yet nothing used to validate it: the .bnix<->.nix
# drift-check never reads dotfile CONTENT, and the hooks are plain shell scripts.
# This is the missing gate. It runs in CI (.github/workflows/claude-config.yml)
# on repo content alone, and with --local it ALSO checks this machine's PATH so a
# CLI the global CLAUDE.md names can't quietly disappear.
#
# HARD FAILS (exit 1): a hook fails shellcheck (-S warning), settings.json is not
# valid JSON, or a wired hook command points at a missing/non-executable file.
# SOFT WARNS: a skill missing SKILL.md frontmatter; --local CLI gaps.
#
# USAGE:  scripts/claude-config-check.sh [--local]
# ============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOT="$REPO/dotfiles/claude"
HOOKS="$DOT/hooks"
SETTINGS="$DOT/settings.json"
LOCAL=0; [ "${1:-}" = "--local" ] && LOCAL=1

fail=0
err()  { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
warn() { printf 'warn: %s\n' "$*" >&2; }
ok()   { printf 'ok:   %s\n' "$*"; }

# 1. shellcheck every hook script (warning severity and up) ------------------
if command -v shellcheck >/dev/null 2>&1; then
  for h in "$HOOKS"/*.sh; do
    [ -e "$h" ] || continue
    if shellcheck -S warning "$h" >/tmp/sc.$$ 2>&1; then
      ok "shellcheck $(basename "$h")"
    else
      err "shellcheck $(basename "$h"):"; cat /tmp/sc.$$ >&2
    fi
    rm -f /tmp/sc.$$
  done
else
  err "shellcheck not found — cannot lint hooks (install it; do not skip the gate)"
fi

# 2. settings.json is valid JSON ---------------------------------------------
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS" 2>/dev/null; then
  ok "settings.json is valid JSON"
else
  err "settings.json is not valid JSON ($SETTINGS)"
fi

# 3. every wired hook command resolves to an existing +x file under hooks/ ----
#    path-style-agnostic: match by basename so absolute, \$HOME, or repo-relative
#    command paths all validate against the tracked hooks/ dir.
if python3 - "$SETTINGS" "$HOOKS" <<'PY'
import json, sys, os
settings, hooks_dir = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(settings))
except Exception as e:
    print(f"FAIL: cannot parse {settings}: {e}", file=sys.stderr); sys.exit(1)
cmds = []
for ev, groups in (cfg.get("hooks") or {}).items():
    for g in groups:
        for h in g.get("hooks", []):
            if h.get("type") == "command" and h.get("command"):
                cmds.append((ev, h["command"]))
bad = 0
for ev, c in cmds:
    base = os.path.basename(c.split()[0])
    p = os.path.join(hooks_dir, base)
    if os.path.isfile(p) and os.access(p, os.X_OK):
        print(f"ok:   hook {ev} -> {base} exists + executable")
    else:
        print(f"FAIL: hook {ev} command not found/executable in hooks/: {c}", file=sys.stderr)
        bad = 1
sys.exit(bad)
PY
then :; else fail=1; fi

# 4. each skill dir has a SKILL.md with frontmatter (soft) -------------------
if [ -d "$DOT/skills" ]; then
  for d in "$DOT"/skills/*/; do
    [ -d "$d" ] || continue
    f="${d}SKILL.md"
    if [ -f "$f" ] && head -1 "$f" | grep -q '^---'; then
      ok "skill $(basename "$d") has SKILL.md frontmatter"
    else
      warn "skill $(basename "$d") has no SKILL.md frontmatter (expected ${f#$DOT/})"
    fi
  done
fi

# 5. --local: the CLIs CLAUDE.md names exist; removed ones stay removed ------
if [ "$LOCAL" -eq 1 ]; then
  for c in lodestar direnv nix; do
    if command -v "$c" >/dev/null 2>&1; then ok "CLI present: $c"
    else err "CLI named in CLAUDE.md is missing from PATH: $c"; fi
  done
  # CLAUDE.md asserts 'los is gone entirely' — make that claim falsifiable.
  if command -v los >/dev/null 2>&1; then
    err "CLAUDE.md says 'los is gone' but 'los' is on PATH — stale claim"
  else
    ok "'los' absent (matches CLAUDE.md)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  printf '\nclaude-config-check: FAILED\n' >&2
  exit 1
fi
printf '\nclaude-config-check: all green\n'
exit 0
