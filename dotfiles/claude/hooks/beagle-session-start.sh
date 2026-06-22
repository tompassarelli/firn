#!/usr/bin/env bash
# SessionStart hook (global, guarded) — the DETERMINISTIC layer of the Beagle
# authoring setup. Skills/CLAUDE.md are model-discretion (can be forgotten);
# this hook is harness-enforced and fires once per session.
#
# In a Beagle project it: (1) revives the daemon + functionally verifies the
# repair loop (beagle-doctor --revive --quiet), and (2) injects the authoring
# handshake into the session context so the agent starts on solid ground.
# Outside a Beagle project it is a fast no-op (a few globs, no heavy work).
set -uo pipefail

# Clean-room / experiment kill-switch (opt-OUT; see claim-canonical-guard.sh).
# When CLAUDE_NO_AUTHORING_HOOKS is set, this hook no-ops — no daemon revive, no
# authoring context injected — so a controlled run keeps an identical neutral
# session surface across all arms. Unset (the default) = normal behavior.
[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

# --- fleet roster registration (any session, any project) ------------------
# If this session declares a fleet handle, put it on the ONE :7978 roster + start its heartbeat.
# This is what merges the interactive and headless rosters into a single truth of who's live, so a
# headless spawn can refuse to duplicate a handle Tom is driving by hand. No-op without FLEET_HANDLE.
if [ -n "${FLEET_HANDLE:-}" ] && [ -x "$HOME/code/fleet-data/fleet-register.sh" ]; then
  "$HOME/code/fleet-data/fleet-register.sh" "$FLEET_HANDLE" "$PPID" >/dev/null 2>&1 || true
fi

# Project dir: Claude Code sets CLAUDE_PROJECT_DIR; fall back to cwd.
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$dir" 2>/dev/null || exit 0

# --- fast Beagle-context detection (cheap; gate all heavy work behind it) ---
is_beagle() {
  # Definitive: under the beagle checkout (or a worktree of it).
  case "$dir" in
    */code/beagle|*/code/beagle/*|*/code/beagle-*) return 0 ;;
  esac
  # Active beagle project: the daemon/cache marker dir.
  [ -d "$dir/.beagle" ] && return 0
  # Beagle sources at the project root or src/ (precise — NOT a broad subdir
  # scan, so a parent dir like ~ or /tmp that merely contains a beagle project
  # one level down does not trigger).
  local g
  for g in *.bclj *.bcljs *.bjs *.bnix *.bgl \
           src/*.bclj src/*.bcljs src/*.bjs src/*.bnix; do
    [ -e "$g" ] && return 0
  done
  return 1
}
is_beagle || exit 0

# Resolve the `beagle` CLI robustly — beagle tools are NOT on the global PATH;
# they live in the checkout (direnv-activated) or are reached via $BEAGLE_PATH.
# Try, in order: $BEAGLE_PATH/bin, the canonical ~/code/beagle checkout, PATH.
# (The canonical checkout's beagle self-resolves racket via its own .direnv,
# so it runs from any cwd.) We invoke `beagle doctor`, the unified CLI.
beagle=""
[ -n "${BEAGLE_PATH:-}" ] && [ -x "$BEAGLE_PATH/bin/beagle" ] && beagle="$BEAGLE_PATH/bin/beagle"
[ -z "$beagle" ] && [ -x "$HOME/code/beagle/bin/beagle" ] && beagle="$HOME/code/beagle/bin/beagle"
[ -z "$beagle" ] && command -v beagle >/dev/null 2>&1 && beagle="$(command -v beagle)"
[ -n "$beagle" ] || exit 0

# --- functional handshake + self-heal (fast path: daemon + canaries) --------
verdict="$("$beagle" doctor --revive --quiet "$dir" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  line="Repair loop verified healthy (daemon up + functional canaries green)."
else
  line="Repair loop DEGRADED — fix before trusting feedback. Detail: $(printf '%s' "$verdict" | tr '\n' ' ' | cut -c1-400)"
fi

ctx="Beagle project detected. ${line} Before editing Beagle, follow the beagle-authoring skill: run \`beagle-doctor --deep\` (functional handshake), treat the compiler as the source of truth (query beagle-* tools; never trust a static form/type/stdlib list), and trust the PostToolUse repair hook's per-edit feedback. If this project has no repair hook yet, scaffold it with \`beagle-init --hooks\`."

# Inject into session context via the SessionStart additionalContext channel.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$ctx"
exit 0
