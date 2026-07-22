#!/usr/bin/env bash
# SessionStart hook (global, guarded) — the DETERMINISTIC layer of the Beagle
# authoring setup. Skills/AGENTS.md are model-discretion (can be forgotten);
# this hook is harness-enforced at startup, resume, clear, and compact.
#
# In a Beagle project it: (1) starts a throttled, non-blocking repair-loop
# revive, and (2) injects source-aware authoring context. Repeated resumes in
# one session are silent; clear/compact re-inject because they rebuild context.
# Outside a Beagle project it is a fast no-op (a few globs, no heavy work).
set -uo pipefail

# Drain before every decision, including the kill-switch. Keep active-path input
# memory-bounded; an oversized envelope follows the existing malformed no-op.
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

# Clean-room / experiment kill-switch (opt-OUT; see code-upstream-guard.sh).
# When guards are OFF this hook no-ops — no daemon revive, no authoring context
# injected — so a controlled run keeps an identical neutral session surface
# across all arms. Engaged two ways: persistent `north config guards off`
# (state, live), or env CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false;
# 0/false forces guards live). Neither engaged (the default) = normal behavior.
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

# Both Claude Code and Codex pass a SessionStart JSON envelope on stdin. Parse
# it opportunistically: malformed/missing input must never break startup.
event_cwd=""
session_id=""
session_source=""
if [ -n "$payload" ] && command -v python3 >/dev/null 2>&1; then
  mapfile -t event_fields < <(
    printf '%s' "$payload" | python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}

for key in ("cwd", "session_id", "source"):
    value = data.get(key, "")
    print(value if isinstance(value, str) else "")
' 2>/dev/null
  )
  event_cwd="${event_fields[0]:-}"
  session_id="${event_fields[1]:-}"
  session_source="${event_fields[2]:-}"
fi
session_source="${session_source,,}"

# Claude Code sets CLAUDE_PROJECT_DIR. Codex relies on the event cwd. Preserve
# the Claude override, then fall back through the event and process cwd.
dir="${CLAUDE_PROJECT_DIR:-${event_cwd:-$PWD}}"
cd "$dir" 2>/dev/null || exit 0
dir="$(pwd -P)"

# SessionStart is not literally once per session: resume, clear, and compact
# also fire it. An atomic marker keeps ordinary startup/resume idempotent while
# clear/compact deliberately restore context after a context reset.
if [ -n "${BEAGLE_SESSION_STATE_DIR:-}" ]; then
  state_dir="$BEAGLE_SESSION_STATE_DIR"
elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  state_dir="$XDG_RUNTIME_DIR/beagle-session-start"
else
  runtime_uid="${UID:-$(id -u)}"
  state_dir="${TMPDIR:-/tmp}/beagle-session-start-$runtime_uid"
fi
state_ready=0
if mkdir -p "$state_dir" 2>/dev/null; then
  chmod 700 "$state_dir" 2>/dev/null || true
  state_ready=1
fi

state_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  else
    cksum | awk '{print $1}'
  fi
}

dir_key="$(printf '%s' "$dir" | state_hash)"
session_marker=""
if [ -n "$session_id" ]; then
  session_key="$(printf '%s\0%s' "$session_id" "$dir" | state_hash)"
  session_marker="$state_dir/context-$session_key"
fi

claim_session_context() {
  if [ "$state_ready" -eq 0 ] || [ -z "$session_marker" ]; then
    return 0
  fi
  (set -o noclobber; printf '%s\n' "$session_source" >"$session_marker") 2>/dev/null
}

remember_session_context() {
  [ "$state_ready" -eq 1 ] && [ -n "$session_marker" ] || return 0
  printf '%s\n' "$session_source" >"$session_marker" 2>/dev/null || true
}

context_mode=full
context_prepared=0
prepare_context_mode() {
  [ "$context_prepared" -eq 0 ] || return 0
  context_prepared=1
  case "$session_source" in
    clear)
      # /clear discards prior context, so restore the complete handshake.
      remember_session_context
      ;;
    compact)
      # Compaction also rebuilds context, but a concise reminder is enough.
      remember_session_context
      context_mode=compact
      ;;
    startup|resume|"")
      claim_session_context || context_mode=none
      ;;
    *)
      # Unknown providers/sources retain legacy behavior, with dedupe when a
      # stable session id is available.
      claim_session_context || context_mode=none
      ;;
  esac
}

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
  prepare_context_mode
  [ "$context_mode" != none ] || return 0
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

# --- functional handshake + self-heal (NON-BLOCKING, THROTTLED revive) -------
# SessionStart can arrive several times in quick succession. A per-checkout
# advisory lock makes launch admission atomic; its fd is inherited by the
# detached doctor, so a crash releases it automatically. The timestamp adds a
# cooldown after completion without ever becoming a permanent lock.
warm_started=0
warm_ttl="${BEAGLE_SESSION_WARM_TTL_SECONDS:-300}"
case "$warm_ttl" in ""|*[!0-9]*) warm_ttl=300 ;; esac
maybe_start_warm() {
  [ "$state_ready" -eq 1 ] || return 0
  command -v flock >/dev/null 2>&1 || return 0
  command -v setsid >/dev/null 2>&1 || return 0

  local lock="$state_dir/warm-$dir_key.lock"
  local stamp="$state_dir/warm-$dir_key.stamp"
  local now last
  exec 9>"$lock" 2>/dev/null || return 0
  if ! flock -n 9; then
    exec 9>&-
    return 0
  fi

  now="$(date +%s)"
  last="$(cat "$stamp" 2>/dev/null || true)"
  case "$last" in ""|*[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -lt "$warm_ttl" ]; then
    flock -u 9
    exec 9>&-
    return 0
  fi

  printf '%s\n' "$now" >"$stamp" 2>/dev/null || true
  # fd 9 stays inherited by the child until doctor exits; closing the parent's
  # copy below cannot release the child-held lock.
  setsid "$beagle" doctor --revive --quiet "$dir" \
    >"$state_dir/revive-$dir_key.log" 2>&1 </dev/null 9>&9 &
  warm_started=1
  disown 2>/dev/null || true
  exec 9>&-
}
maybe_start_warm

prepare_context_mode
if [ "$context_mode" = none ]; then
  exit 0
fi

warm_ctx=""
if [ "$warm_started" -eq 1 ]; then
  warm_ctx=" A background \`beagle doctor --revive --quiet\` check was started for this checkout."
fi

if [ "$context_mode" = compact ]; then
  ctx="Beagle authoring context restored after compaction. Before the next Beagle edit, run \`beagle doctor --deep\`; treat compiler and PostToolUse repair feedback as authoritative.${warm_ctx}"
else
  ctx="Beagle authoring is active.${warm_ctx} YOU (the agent) own repair-loop health, not the user. Before the first Beagle edit, run \`beagle doctor --deep\` and self-heal if degraded. Treat the compiler as source of truth (query Beagle tools; never trust a static form/type/stdlib list), and trust the PostToolUse repair hook's per-edit feedback. If this project has no repair hook, scaffold it with \`beagle init --hooks\`."
fi
# Append the flip-level announcement (graceful-degradation ladder, L1-L3).
[ -n "$ladder_ctx" ] && ctx="$ctx $ladder_ctx"

# Inject into session context via the SessionStart additionalContext channel.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$ctx"
exit 0
