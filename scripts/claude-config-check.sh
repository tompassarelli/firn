#!/usr/bin/env bash
# claude-config-check.sh — anti-rot validator for the Claude global config surface.
# ============================================================================
# The Claude config (settings.json + hooks + skills + CLAUDE.md) injects behavior
# into every agent session, yet nothing used to validate it: the .bnix<->.nix
# drift-check never reads dotfile CONTENT, and the hooks are plain shell scripts.
# This is the missing gate. It runs in CI (.github/workflows/claude-config.yml)
# on repo content alone, and with --local it ALSO checks this machine's state
# (PATH, the home-manager symlink chain, and the MCP registration in ~/.claude.json)
# so a CLI the global CLAUDE.md names can't quietly disappear and the config
# can't silently rot away from the repo.
#
# HARD FAILS (exit 1): a hook fails shellcheck (-S warning); settings.json is not
# valid JSON; a wired hook command points at a missing/non-executable file;
# autoMemoryEnabled is not false (reproducibility invariant); [--local] a
# ~/.claude entry no longer resolves to the dotfile SoT; [--local] the USER-scope
# MCP set drifts from {fram,north} or fram points at the DEMO corpus.
# SOFT WARNS: a skill missing SKILL.md frontmatter; --local CLI gaps;
# project-scoped MCP servers (reported for visibility).
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

# 3. every wired IN-REPO hook command resolves to an existing +x file --------
#    path-style-agnostic: match by basename so absolute, \$HOME, or repo-relative
#    command paths all validate against the tracked hooks/ dir. Hook commands
#    pointing OUTSIDE the repo (a sibling project's bin/, e.g.
#    ~/code/north/bin/tern-on-spawn) are external — the repo can't vouch
#    for them and CI can't see them, so they're noted, not failed.
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
    cmd_path = c.split()[0]
    d = os.path.dirname(cmd_path).replace(os.sep, "/")
    # External hook: an absolute path that does NOT live under the repo's
    # dotfiles/claude/hooks (a sibling project's bin/, e.g. tern-on-spawn).
    # The repo can't vouch for it and CI can't see it -> note, don't fail.
    # In-repo hooks (bare name, or a path under dotfiles/claude/hooks) are
    # still validated strictly against the tracked hooks/ dir.
    if d and not d.endswith("dotfiles/claude/hooks"):
        print(f"note: hook {ev} -> external {cmd_path} (outside repo; not checked)")
        continue
    base = os.path.basename(cmd_path)
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

# 5. reproducibility invariant: autoMemoryEnabled must be false (repo content) -
#    Auto-memory writes untracked, machine-local, self-mutating state under
#    ~/.claude/projects/*/memory/ — it violates the "everything in the Claude
#    config is nix-managed + committed" thesis. This is the falsifiable guard.
if python3 - "$SETTINGS" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
v = cfg.get("autoMemoryEnabled")
if v is False:
    print("ok:   autoMemoryEnabled is false (reproducibility invariant)"); sys.exit(0)
print(f"FAIL: autoMemoryEnabled must be false (reproducibility invariant), got {v!r}", file=sys.stderr)
sys.exit(1)
PY
then :; else fail=1; fi

# 6. --local: the CLIs CLAUDE.md names exist; removed ones stay removed ------
if [ "$LOCAL" -eq 1 ]; then
  for c in north direnv nix; do
    if command -v "$c" >/dev/null 2>&1; then ok "CLI present: $c"
    else err "CLI named in CLAUDE.md is missing from PATH: $c"; fi
  done
  # CLAUDE.md asserts 'los is gone entirely' — make that claim falsifiable.
  if command -v los >/dev/null 2>&1; then
    err "CLAUDE.md says 'los is gone' but 'los' is on PATH — stale claim"
  else
    ok "'los' absent (matches CLAUDE.md)"
  fi

  # 7. --local: each nix-managed ~/.claude entry resolves to the dotfile SoT.
  #    Catches a stale/broken home-manager generation (the EROFS read-only-symlink
  #    failure) before it silently desyncs the live config from the repo.
  for entry in settings.json skills hooks CLAUDE.md commands; do
    link="$HOME/.claude/$entry"
    if [ ! -e "$link" ]; then
      err ".claude/$entry is missing (home-manager not applied?)"; continue
    fi
    real="$(readlink -f "$link" 2>/dev/null)"
    case "$real" in
      "$DOT"/*) ok ".claude/$entry resolves to dotfiles/claude/" ;;
      *)        err ".claude/$entry resolves to '$real', not dotfiles/claude/ (stale home-manager generation)" ;;
    esac
  done

  # 8. --local: MCP registration in ~/.claude.json — the exact rot that pointed
  #    fram at the demo corpus on 2026-06-23. USER scope must be EXACTLY the
  #    declared set (fram,north + the Linear MSA server); fram must target
  #    the LIVE store, never the repo demo.
  CJSON="$HOME/.claude.json"
  if [ -f "$CJSON" ]; then
    if python3 - "$CJSON" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
servers = cfg.get("mcpServers") or {}
allow = {"fram", "north", "linear-mcp-msa-new"}
rc = 0
for name in servers:
    if name not in allow:
        print(f"FAIL: unexpected USER-scope MCP server '{name}' (nix declares only {sorted(allow)}) — drift", file=sys.stderr); rc = 1
for need in sorted(allow):
    if need not in servers:
        print(f"FAIL: MCP server '{need}' not registered (USER scope)", file=sys.stderr); rc = 1
fram = servers.get("fram") or {}
log = (fram.get("env") or {}).get("FRAM_LOG", "")
if not log:
    print("FAIL: fram MCP has no FRAM_LOG -> falls back to the repo DEMO corpus (footgun)", file=sys.stderr); rc = 1
elif "/code/fram" in log:
    print(f"FAIL: fram MCP points at the DEMO corpus ({log}) — must be the live store", file=sys.stderr); rc = 1
elif "north" in log:
    print(f"ok:   fram MCP -> live corpus ({log})")
else:
    print(f"warn: fram FRAM_LOG set but unrecognized ({log})", file=sys.stderr)
proj = {k: list((v.get("mcpServers") or {}).keys())
        for k, v in (cfg.get("projects") or {}).items()
        if isinstance(v, dict) and v.get("mcpServers")}
for path, names in proj.items():
    print(f"note: project-scoped MCP in {path}: {names}")
sys.exit(rc)
PY
    then :; else fail=1; fi
  else
    warn ".claude.json not found — cannot check MCP registration"
  fi
fi

if [ "$fail" -ne 0 ]; then
  printf '\nclaude-config-check: FAILED\n' >&2
  exit 1
fi
printf '\nclaude-config-check: all green\n'
exit 0
