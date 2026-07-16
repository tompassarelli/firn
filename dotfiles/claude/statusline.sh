#!/usr/bin/env bash
# Claude Code status line — modular, per-segment toggles.
#
# Claude Code's status line is ONE command: whatever this script prints to
# stdout IS the entire line. There is no segment bus. So this file IS the bus —
# it composes the line from independent SEGMENTS, each with its own on/off
# switch. Flip a SEGMENT_* below to drop exactly one piece while the rest of the
# line stays — the modularity the single-slot design otherwise lacks.
#
# Wired from ~/code/nixos-config/dotfiles/claude/settings.json (statusLine.command).
# Edit HERE, never in ~/.claude — settings.json there is a symlink to this repo.

# ── segment switches (on|off) ───────────────────────────────────────────────
# Each honors a same-named env override; the ${..:-default} is the baked default.
SEGMENT_CAVEMAN="${SEGMENT_CAVEMAN:-on}"   # [CAVEMAN] / [CAVEMAN:MODE] mode chip
# future: SEGMENT_MODEL, SEGMENT_CONTEXT, SEGMENT_GIT … (read the session JSON
# Claude Code pipes on stdin — captured below for whoever needs it).

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STDIN_JSON=$(cat 2>/dev/null)   # session payload; entitlement observer + future segments
segments=()

# Claude.ai subscriber limits arrive in this already-local payload after the
# first response. Hand them to North without an API call, credential read, model
# turn, or statusline dependency: the detached observer is silent and fail-open.
forward_rate_limits() {
  local north="$HOME/code/north/bin/north"
  [ -x "$north" ] || return
  case "$STDIN_JSON" in *'"rate_limits"'*) ;; *) return ;; esac
  local runtime="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  local lock="$runtime/north-claude-statusline-${UID}.lock" lock_fd
  command -v flock >/dev/null 2>&1 || return
  exec {lock_fd}> "$lock"
  if ! flock -n "$lock_fd"; then exec {lock_fd}>&-; return; fi
  {
    printf '%s' "$STDIN_JSON" | "$north" provider-observe claude-statusline
    sleep 1
  } >/dev/null 2>&1 &
  # The detached worker inherited the locked open-file description. Closing the
  # statusline's copy keeps rendering non-blocking; kernel release is automatic
  # even if the observer crashes.
  exec {lock_fd}>&-
}
forward_rate_limits

# ── caveman: is caveman on, and in what mode ────────────────────────────────
# Self-contained: reads caveman's own flag file directly, no plugin dependency,
# and deliberately ignores the savings-suffix file (that number is a fixed
# multiple of output tokens, not a measurement). Orange = active, grey =
# installed-but-off, nothing = not installed.
caveman_segment() {
  local flag="$CLAUDE_DIR/.caveman-active"
  [ -L "$flag" ] && return            # refuse symlink: blocks ANSI-escape injection via the flag
  [ -f "$flag" ] || return            # absent → caveman not installed → render nothing
  # Pure bash, no forks (this runs on every prompt render). || true, not || mode="":
  # read returns 1 on a no-trailing-newline flag file but has already set mode.
  local mode=""
  IFS= read -r mode < "$flag" 2>/dev/null || true
  mode=${mode,,}; mode=${mode//[^a-z0-9-]/}; mode=${mode:0:32}
  case "$mode" in
    off|lite|full|ultra|wenyan|wenyan-lite|wenyan-full|wenyan-ultra|commit|review|compress) ;;
    *) return ;;                       # unknown/empty → render nothing, never echo raw bytes
  esac
  local color=172                      # orange = active
  [ "$mode" = off ] && color=240       # grey = installed but off
  printf '\033[38;5;%sm[CAVEMAN:%s]\033[0m' "$color" "${mode^^}"
}

[ "$SEGMENT_CAVEMAN" = on ] && { s=$(caveman_segment); [ -n "$s" ] && segments+=("$s"); }

# ── render: join active segments with a single space ────────────────────────
( IFS=' '; printf '%s' "${segments[*]}" )
