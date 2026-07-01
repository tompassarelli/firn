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

# --- functional handshake + self-heal (NON-BLOCKING revive) -----------------
# The revive cold-starts the racket daemon (~20s). Run synchronously it stalls
# the FIRST user turn — Claude blocks that turn on this hook's exit (SessionStart
# additionalContext channel). So detach it: `setsid … &` runs the revive in its
# own session (immune to this hook's process-group teardown) and the hook returns
# instantly. No synchronous boot-time verdict — health is the AGENT's job to
# confirm on demand (and the PostToolUse repair hook self-heals per edit). Output
# goes to a debug log NOBODY is asked to watch.
setsid "$beagle" doctor --revive --quiet "$dir" >"${TMPDIR:-/tmp}/beagle-revive.log" 2>&1 </dev/null &
line="The repair daemon is warming in the background (non-blocking)."

ctx="Beagle project detected. ${line} YOU (the agent) own repair-loop health, not the user — never ask them to check a log or babysit the daemon. Before your first Beagle edit, confirm the daemon is live yourself with \`beagle-doctor --deep\` (functional handshake) and self-heal if degraded. Treat the compiler as source of truth (query beagle-* tools; never trust a static form/type/stdlib list), and trust the PostToolUse repair hook's per-edit feedback. If this project has no repair hook yet, scaffold it with \`beagle-init --hooks\`."

# Inject into session context via the SessionStart additionalContext channel.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$ctx"
exit 0
