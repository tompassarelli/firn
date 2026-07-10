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

# Clean-room / experiment kill-switch (opt-OUT; see code-upstream-guard.sh).
# When guards are OFF this hook no-ops — no daemon revive, no authoring context
# injected — so a controlled run keeps an identical neutral session surface
# across all arms. Engaged two ways: persistent `north config guards off`
# (state, live), or env CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false;
# 0/false forces guards live). Neither engaged (the default) = normal behavior.
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

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

# --- graceful-degradation ladder (L0-L3): flip-level facts + announcement ----
# fram-code-status is filesystem + a loopback port probe (<100ms, no racket).
# GUARDED: any failure (helper missing, timeout, bad output) leaves ladder_ctx
# empty and the hook proceeds exactly as before — this block can never fail it.
ladder_ctx=""
_fcs="$HOME/code/fram/bin/fram-code-status"
if [ -x "$_fcs" ]; then
  _facts="$(timeout 2 "$_fcs" "$dir" 2>/dev/null)" || _facts=""
  if [ -n "$_facts" ]; then
    _fact() { printf '%s\n' "$_facts" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -1; }
    _level="$(_fact level)"
    case "$_level" in
      3) ladder_ctx="[flip L3] graph-native: author via mcp__fram__* graph-edit verbs (add-def/set-body/rename-def/insert-after); ask the graph first (blast-radius/query) before reading files; registered graph-upstream files REFUSE text edits ($(_fact canonical) registered here; coordinator alive on :$(_fact port), $(_fact facts) facts)." ;;
      2) ladder_ctx="[flip L2] this repo is flipped (.fram/code.log with $(_fact facts) facts + .mcp.json) but the warm coordinator is NOT alive (port $(_fact port)). Revive: \`fram-code-on $dir\` re-warms it; then restart Claude Code here for the mcp__fram__* graph-edit verbs." ;;
      1) ladder_ctx="[flip L1] flippable: $(_fact src) Beagle source file(s), not flipped. \`fram-code-on $dir [--src <subdir>]\` turns on graph-native authoring (ingest -> warm coordinator -> mcp__fram__* graph-edit verbs)." ;;
      *) ladder_ctx="" ;;  # L0 or unparseable: stay silent
    esac
    # The graph-upstream guard refuses text edits at ANY level — warn early so
    # a session in a de-flipped repo isn't surprised by a PreToolUse deny.
    if [ -n "$ladder_ctx" ] && [ "$_level" != "3" ] && [ "$(_fact canonical)" != "0" ]; then
      ladder_ctx="$ladder_ctx Note: $(_fact canonical) graph-upstream file(s) under this repo are registered and REFUSE text edits regardless of flip level."
    fi
  fi
fi
# Emit ONLY the ladder context (early-exit paths where the full Beagle handshake
# doesn't apply). Same SessionStart additionalContext channel as the main print.
emit_ladder_ctx() {
  [ -n "$ladder_ctx" ] || return 0
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$ladder_ctx" || true
}

# Not a Beagle project by the precise root/src probe — but the ladder scan is
# recursive, so a repo whose Beagle sources are all NESTED (or an already-flipped
# repo) still gets its flip level announced. L0 stays silent (empty ladder_ctx).
if ! is_beagle; then
  emit_ladder_ctx
  exit 0
fi

# Resolve the `beagle` CLI robustly — beagle tools are NOT on the global PATH;
# they live in the checkout (direnv-activated) or are reached via $BEAGLE_PATH.
# Try, in order: $BEAGLE_PATH/bin, the canonical ~/code/beagle checkout, PATH.
# (The canonical checkout's beagle self-resolves racket via its own .direnv,
# so it runs from any cwd.) We invoke `beagle doctor`, the unified CLI.
beagle=""
[ -n "${BEAGLE_PATH:-}" ] && [ -x "$BEAGLE_PATH/bin/beagle" ] && beagle="$BEAGLE_PATH/bin/beagle"
[ -z "$beagle" ] && [ -x "$HOME/code/beagle/bin/beagle" ] && beagle="$HOME/code/beagle/bin/beagle"
[ -z "$beagle" ] && command -v beagle >/dev/null 2>&1 && beagle="$(command -v beagle)"
if [ -z "$beagle" ]; then
  emit_ladder_ctx   # flip level is still worth announcing without the beagle CLI
  exit 0
fi

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
# Append the flip-level announcement (graceful-degradation ladder, L1-L3).
[ -n "$ladder_ctx" ] && ctx="$ctx $ladder_ctx"

# Inject into session context via the SessionStart additionalContext channel.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$ctx"
exit 0
