#!/usr/bin/env bash
# shellcheck disable=SC2016 # Dollar-prefixed names in single quotes are jq variables.
#
# Reconcile the user-scope MCP servers Claude should know about (North, FRAM,
# Linear) from the GENERATED Claude state, deciding presence and shape purely
# STRUCTURALLY from ~/.claude.json — never from a health probe.
#
# `claude mcp get`/`list` always connect to the server (a health check) and
# have no config-only mode. A transiently-down server must therefore never read
# as a missing declaration and trigger a destructive `mcp remove` + `mcp add`.
# This script inspects the declaration directly and only re-registers when the
# declared command/url/env genuinely differs from the intended shape. Health is
# a separate, bounded, report-only path (`--health`) that never mutates state.
set -uo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
JQ_BIN="${JQ_BIN:-jq}"
TIMEOUT_BIN="${TIMEOUT_BIN:-timeout}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"
LIFE="${LIFE:-$HOME/.local/state/north}"
FRAM_MCP_BIN="${FRAM_MCP_BIN:-$HOME/code/fram/bin/fram-mcp}"
NORTH_MCP_BIN="${NORTH_MCP_BIN:-$HOME/code/north/bin/north-mcp}"
LINEAR_URL="${LINEAR_URL:-https://mcp.linear.app/mcp}"
WANT_NORTH_PORT="${WANT_NORTH_PORT:-7977}"
MUTATION_TIMEOUT_SECONDS="${MUTATION_TIMEOUT_SECONDS:-30}"
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-15}"

WANT_FRAM_LOG="$LIFE/coordination.log"
WANT_FRAM_TELEMETRY_LOG="$LIFE/telemetry.log"
WANT_FRAM_THREADS="$LIFE/threads"

warn() {
  printf '%s\n' "$*" >&2
}

# Pure structural read of a declared server object from generated Claude state.
# No connection, no health check. Prints the server's JSON, or empty if absent.
declared_server() {
  local name="$1"
  [ -f "$CLAUDE_JSON" ] || return 0
  "$JQ_BIN" -c --arg name "$name" \
    '(.mcpServers[$name] // empty)' "$CLAUDE_JSON" 2>/dev/null || true
}

# True when the declared JSON already matches the intended shape. jq args and
# the predicate expression are supplied by the caller.
declaration_matches() {
  local json="$1"
  shift
  [ -n "$json" ] || return 1
  "$JQ_BIN" -e "$@" >/dev/null 2>&1 <<<"$json"
}

# Re-register a server ONLY because its structural declaration is missing or
# wrong — never because a health probe failed. A stale declaration is removed
# first so the add cannot collide, then the supported user-scope add is run
# under a hard deadline.
reconcile_server() {
  local name="$1" declared="$2" matched="$3"
  shift 3
  [ "$matched" = 1 ] && return 0
  if [ -n "$declared" ]; then
    "$TIMEOUT_BIN" "$MUTATION_TIMEOUT_SECONDS" \
      "$CLAUDE_BIN" mcp remove "$name" -s user >/dev/null 2>&1 || true
  fi
  "$TIMEOUT_BIN" "$MUTATION_TIMEOUT_SECONDS" "$CLAUDE_BIN" mcp "$@" ||
    warn "warning: could not register MCP server $name; agent-config-check --local will report the drift"
}

reconcile_declarations() {
  local fram_json north_json linear_json fram_ok north_ok linear_ok

  fram_json="$(declared_server fram)"
  declaration_matches "$fram_json" \
    --arg cmd "$FRAM_MCP_BIN" \
    --arg log "$WANT_FRAM_LOG" \
    --arg tel "$WANT_FRAM_TELEMETRY_LOG" \
    --arg thr "$WANT_FRAM_THREADS" \
    '((.type // "stdio") == "stdio")
       and (.command == $cmd)
       and (.env.FRAM_LOG == $log)
       and (.env.FRAM_TELEMETRY_LOG == $tel)
       and (.env.FRAM_THREADS == $thr)' &&
    fram_ok=1 || fram_ok=0
  reconcile_server fram "$fram_json" "$fram_ok" \
    add fram -s user \
    -e "FRAM_LOG=$WANT_FRAM_LOG" \
    -e "FRAM_TELEMETRY_LOG=$WANT_FRAM_TELEMETRY_LOG" \
    -e "FRAM_THREADS=$WANT_FRAM_THREADS" \
    -- "$FRAM_MCP_BIN"

  north_json="$(declared_server north)"
  declaration_matches "$north_json" \
    --arg cmd "$NORTH_MCP_BIN" \
    --arg log "$WANT_FRAM_LOG" \
    --arg tel "$WANT_FRAM_TELEMETRY_LOG" \
    --arg thr "$WANT_FRAM_THREADS" \
    --arg port "$WANT_NORTH_PORT" \
    '((.type // "stdio") == "stdio")
       and (.command == $cmd)
       and (.env.FRAM_LOG == $log)
       and (.env.FRAM_TELEMETRY_LOG == $tel)
       and (.env.FRAM_THREADS == $thr)
       and (.env.NORTH_PORT == $port)' &&
    north_ok=1 || north_ok=0
  reconcile_server north "$north_json" "$north_ok" \
    add north -s user \
    -e "FRAM_LOG=$WANT_FRAM_LOG" \
    -e "FRAM_TELEMETRY_LOG=$WANT_FRAM_TELEMETRY_LOG" \
    -e "FRAM_THREADS=$WANT_FRAM_THREADS" \
    -e "NORTH_PORT=$WANT_NORTH_PORT" \
    -- "$NORTH_MCP_BIN"

  linear_json="$(declared_server linear-mcp-msa-new)"
  declaration_matches "$linear_json" \
    --arg url "$LINEAR_URL" \
    '(.type == "http") and (.url == $url)' &&
    linear_ok=1 || linear_ok=0
  reconcile_server linear-mcp-msa-new "$linear_json" "$linear_ok" \
    add --transport http linear-mcp-msa-new "$LINEAR_URL" -s user
}

# Bounded, report-only health. Kept strictly separate from declaration
# reconciliation: a slow or failing probe is surfaced, never acted on.
report_health() {
  local name status
  for name in fram north linear-mcp-msa-new; do
    "$TIMEOUT_BIN" "$HEALTH_TIMEOUT_SECONDS" \
      "$CLAUDE_BIN" mcp get "$name" >/dev/null 2>&1
    status=$?
    if [ "$status" -eq 0 ]; then
      printf 'mcp health: %s ok\n' "$name" >&2
    else
      printf 'mcp health: %s probe exited %s (declaration left intact)\n' \
        "$name" "$status" >&2
    fi
  done
}

if [ "${1:-}" = "--health" ]; then
  report_health
  exit 0
fi

reconcile_declarations
