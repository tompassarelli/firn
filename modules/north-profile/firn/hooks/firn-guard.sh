#!/usr/bin/env bash
# PreToolUse guard — firn nixos-config.
# ============================================================================
# Two jobs, both deterministic (a CLAUDE.md line is model-discretion and gets
# forgotten — this hook is the layer that can't be):
#
#   1. INJECT the repo's non-negotiable rules as additionalContext the FIRST
#      time a session edits anything under ~/code/nixos-config (incl. the
#      ~/.claude/* symlinks, which resolve into the repo). The edit still
#      proceeds — we just guarantee the rules are in context. This is the fix
#      for "agent edited .nix by hand because it never read nixos-config/CLAUDE.md."
#
#   2. DENY bypasses around the sanctioned rebuild wrapper: nixos-rebuild / nh /
#      darwin-rebuild switch and flake upgrades stay the USER's. `firn rebuild`
#      remains agent-runnable.
#
# Kill-switch: persistent `north config guards off` (state) OR env
# CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces guards live).
# Shared impl: lib/authoring-killswitch.sh.
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
# `north config guards off` (state, live) or env CLAUDE_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

read -r -d '' PY <<'PYEOF' || true
import sys, json, os, re

def allow():
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    allow()

tool = data.get("tool_name", "")
ti = data.get("tool_input", {}) or {}
session = str(data.get("session_id", "nosession"))

NIXOS = "/code/nixos-config/"

DIGEST = (
    "⚠ You are editing the firn nixos-config repo (~/code/nixos-config). "
    "Follow its CLAUDE.md. Non-negotiable:\n"
    "1. Edit .bnix sources, NEVER .nix. The .nix is GENERATED; `firn repo build` "
    "overwrites hand-edits. Host config too: hosts/<host>/configuration.bnix, not .nix.\n"
    "2. After any .bnix change: run `firn repo build` then `firn repo validate`. git add BOTH "
    "the .bnix AND the generated .nix (the flake only sees git-tracked files).\n"
    "3. `firn rebuild` is agent-runnable after `firn repo build` + `firn repo validate` are green "
    "and your changes are COMMITTED. It builds a commit snapshot, so concurrent "
    "uncommitted work cannot enter the generation. Raw `nixos-rebuild switch` / "
    "`nh switch` / `firn repo upgrade now` stay USER-only.\n"
    "4. Secrets: sops-nix only (secrets/*.yaml). Never plaintext creds in the repo.\n"
    "5. New module = create modules/<name>/default.bnix, `firn repo build`, git add both files "
    "(flake auto-imports the dir). Enable it in hosts/<host>/configuration.bnix or via a tag.\n"
    "Invoke the `firn` skill for the full workflow."
)

# --- Job 1: inject rules once per session on a nixos-config edit ---
if tool in ("Edit", "Write", "MultiEdit"):
    fp = ti.get("file_path") or ti.get("filePath") or ""
    try:
        real = os.path.realpath(fp)
    except Exception:
        real = fp
    if NIXOS in (real + "/") or NIXOS in (fp + "/"):
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", session)
        # XDG_RUNTIME_DIR: per-user tmpfs, cleared at logout — /tmp markers pile up until reboot.
        marker = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "claude-firn-guard.%s" % safe)
        if not os.path.exists(marker):
            try:
                open(marker, "w").close()
            except Exception:
                pass
            # Decision-less on purpose: emitting "allow" here auto-approved the session's
            # FIRST nixos-config edit as a side effect of injecting context. No decision
            # = normal permission flow; additionalContext still lands.
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": DIGEST,
                }
            }))
            sys.exit(0)
    allow()

# --- Job 2: deny system-switching commands ---
# Anchor every pattern at command position (start of string, after a shell
# separator, or after sudo/doas) so we match a real INVOCATION — not a mere
# mention of the string inside an echo / grep / doc-write argument.
ANCHOR = r"(?:^|[\n;&|(`])\s*(?:sudo\s+|doas\s+)?"

# Raw nixos-rebuild/darwin-rebuild/nh bypass the sanctioned wrapper, and
# `firn repo upgrade now` performs wholesale input bumps and remains user-gated.
SWITCH = re.compile(
    ANCHOR + r"("
    r"firn\s+repo\s+upgrade\s+now\b"
    r"|nixos-rebuild\b[^\n]*\b(?:switch|boot|test)\b"
    r"|darwin-rebuild\b[^\n]*\b(?:switch|boot)\b"
    r"|nh\s+(?:os\s+)?(?:switch|boot)\b"
    r")"
)

# Every deny in this job carries the same escape hatch, stated the same way.
ESCAPE = (
    "Rare deliberate override: `north config guards off` (persistent, live). "
    "A CLAUDE_NO_AUTHORING_HOOKS=1 PREFIX on this command does NOT work — the "
    "guard reads its own env before the command runs; only a session LAUNCHED "
    "with CLAUDE_NO_AUTHORING_HOOKS=1 bypasses it."
)

def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


if tool == "Bash":
    cmd = ti.get("command", "") or ""
    if SWITCH.search(cmd):
        deny(
            "BLOCKED: that command switches the system OUTSIDE the sanctioned path. "
            "Raw nixos-rebuild/darwin-rebuild/nh and `firn repo upgrade now` stay the USER's. "
            "Agents may run `firn rebuild` after the relevant checks pass and their "
            "own changes are committed. "
            + ESCAPE
        )
    allow()

allow()
PYEOF

# Fast-path: this hook fires on EVERY Bash/Edit/Write/MultiEdit in ALL projects, and
# python3 startup is ~40ms. The case filter covers everything python acts on in
# practice: Job 1 needs "nixos-config" in the path OR a ~/.claude/* symlink that
# realpath-resolves into the repo (hence *.claude*); Job 2 needs firn/nixos-rebuild/
# darwin-rebuild/nh in the command — bare *nh* over-matches on purpose: false positives
# just fall through to python, which still decides. (Not a strict superset: a
# non-.claude symlink into the repo would slip past; none exist today.)
case "$payload" in
  *nixos-config*|*.claude*|*firn*|*nixos-rebuild*|*darwin-rebuild*|*nh*) ;;
  *) exit 0 ;;
esac
printf '%s' "$payload" | python3 -c "$PY"
