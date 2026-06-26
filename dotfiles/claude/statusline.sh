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
STDIN_JSON=$(cat 2>/dev/null)   # session payload; unused by caveman, here for new segments
: "${STDIN_JSON:=}"
segments=()

# ── caveman: is caveman on, and in what mode ────────────────────────────────
# Self-contained: reads caveman's own flag file directly, no plugin dependency,
# and deliberately ignores the savings-suffix file (that number is a fixed
# multiple of output tokens, not a measurement). Orange = active, grey =
# installed-but-off, nothing = not installed.
caveman_segment() {
  local flag="$CLAUDE_DIR/.caveman-active"
  [ -L "$flag" ] && return            # refuse symlink: blocks ANSI-escape injection via the flag
  [ -f "$flag" ] || return            # absent → caveman not installed → render nothing
  local mode
  mode=$(head -c 64 "$flag" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  case "$mode" in
    off|lite|full|ultra|wenyan|wenyan-lite|wenyan-full|wenyan-ultra|commit|review|compress) ;;
    *) return ;;                       # unknown/empty → render nothing, never echo raw bytes
  esac
  local color=172                      # orange = active
  [ "$mode" = off ] && color=240       # grey = installed but off
  printf '\033[38;5;%sm[CAVEMAN:%s]\033[0m' "$color" "$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')"
}

[ "$SEGMENT_CAVEMAN" = on ] && { s=$(caveman_segment); [ -n "$s" ] && segments+=("$s"); }

# ── render: join active segments with a single space ────────────────────────
( IFS=' '; printf '%s' "${segments[*]}" )
