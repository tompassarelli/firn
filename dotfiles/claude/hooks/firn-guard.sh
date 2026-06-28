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
#   2. DENY system-switching commands (firn rebuild / nixos-rebuild switch /
#      nh switch / darwin-rebuild switch / firn update). Per nixos-config
#      CLAUDE.md the switch is the USER's to run — agents prepare + verify only.
#
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 disables this (same as the other guards).
# ============================================================================
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

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
    "1. Edit .bnix sources, NEVER .nix. The .nix is GENERATED; `firn build` "
    "overwrites hand-edits. Host config too: hosts/<host>/configuration.bnix, not .nix.\n"
    "2. After any .bnix change: run `firn build` then `firn validate`. git add BOTH "
    "the .bnix AND the generated .nix (the flake only sees git-tracked files).\n"
    "3. Do NOT run `firn rebuild` / `nixos-rebuild switch` / `nh switch` — that "
    "activates the system (sudo, new generation). Leave the switch to the USER. "
    "Verify with `firn validate` or `nix build --no-link`.\n"
    "4. Secrets: sops-nix only (secrets/*.yaml). Never plaintext creds in the repo.\n"
    "5. New module = create modules/<name>/default.bnix, `firn build`, git add both files "
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
        marker = os.path.join("/tmp", "claude-firn-guard.%s" % safe)
        if not os.path.exists(marker):
            try:
                open(marker, "w").close()
            except Exception:
                pass
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                    "additionalContext": DIGEST,
                }
            }))
            sys.exit(0)
    allow()

# --- Job 2: deny system-switching commands ---
if tool == "Bash":
    cmd = ti.get("command", "") or ""
    # Anchor at command position (start of string, after a shell separator, or
    # after sudo/doas) so we match a real INVOCATION — not a mere mention of the
    # string inside an echo / grep / doc-write argument.
    switch = re.compile(
        r"(?:^|[\n;&|(`])\s*(?:sudo\s+|doas\s+)?("
        r"firn\s+(?:host\s+)?rebuild\b"
        r"|firn\s+update(?!\s+--(?:no-rebuild|dry-run))\b"
        r"|nixos-rebuild\b[^\n]*\b(?:switch|boot|test)\b"
        r"|darwin-rebuild\b[^\n]*\b(?:switch|boot)\b"
        r"|nh\s+(?:os\s+)?(?:switch|boot)\b"
        r")"
    )
    if switch.search(cmd):
        reason = (
            "BLOCKED: that command switches the system (sudo / new generation). "
            "Per ~/code/nixos-config/CLAUDE.md the rebuild is the USER's to run, not the agent's. "
            "Prepare + verify instead: `firn build` then `firn validate` (or `nix build --no-link`), "
            "then tell the user to run `firn rebuild` themselves (they can type `! firn rebuild`). "
            "Rare explicit override: prefix with CLAUDE_NO_AUTHORING_HOOKS=1."
        )
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }))
        sys.exit(0)
    allow()

allow()
PYEOF

exec python3 -c "$PY"
