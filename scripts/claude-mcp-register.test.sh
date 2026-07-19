#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/claude-mcp-register.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

REAL_TIMEOUT="$(command -v timeout)"
JQ="$(command -v jq)"

LIFE="$SCRATCH/life"
FRAM_MCP_BIN="$SCRATCH/fram-mcp"
NORTH_MCP_BIN="$SCRATCH/north-mcp"
LINEAR_URL="https://mcp.linear.app/mcp"
WANT_NORTH_PORT="7977"
CLAUDE_JSON="$SCRATCH/claude.json"
CALL_LOG="$SCRATCH/claude-calls"

WANT_FRAM_LOG="$LIFE/coordination.log"
WANT_FRAM_TELEMETRY_LOG="$LIFE/telemetry.log"
WANT_FRAM_THREADS="$LIFE/threads"

# Fake Claude: records every argv and simulates the two distinct surfaces —
# `mcp get` is the health/connect probe (fails or hangs when the server is
# down), while `mcp add`/`mcp remove` mutate declarations. It NEVER lets a
# health outcome influence a declaration.
cat >"$SCRATCH/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALL_LOG"
case "$1 $2" in
  'mcp get')
    [ "${GET_SLEEP:-0}" = 0 ] || sleep "$GET_SLEEP"
    exit "${GET_EXIT:-1}"
    ;;
  'mcp add') exit "${ADD_EXIT:-0}" ;;
  'mcp remove') exit "${REMOVE_EXIT:-0}" ;;
esac
exit 0
SH
chmod +x "$SCRATCH/claude"

write_claude_json() {
  # $1: fram|north|linear|all-correct|empty markers via env overrides
  "$JQ" -n \
    --arg fram_cmd "${FRAM_CMD:-$FRAM_MCP_BIN}" \
    --arg north_cmd "${NORTH_CMD:-$NORTH_MCP_BIN}" \
    --arg log "$WANT_FRAM_LOG" \
    --arg tel "$WANT_FRAM_TELEMETRY_LOG" \
    --arg thr "$WANT_FRAM_THREADS" \
    --arg port "${NORTH_PORT_VAL:-$WANT_NORTH_PORT}" \
    --arg url "$LINEAR_URL" \
    '{mcpServers: {
        fram: {type:"stdio", command:$fram_cmd, args:[],
               env:{FRAM_LOG:$log, FRAM_TELEMETRY_LOG:$tel, FRAM_THREADS:$thr}},
        north: {type:"stdio", command:$north_cmd, args:[],
                env:{FRAM_LOG:$log, FRAM_TELEMETRY_LOG:$tel, FRAM_THREADS:$thr, NORTH_PORT:$port}},
        "linear-mcp-msa-new": {type:"http", url:$url}
      }}' >"$CLAUDE_JSON"
}

run_register() {
  : >"$CALL_LOG"
  env \
    CLAUDE_BIN="$SCRATCH/claude" \
    JQ_BIN="$JQ" \
    TIMEOUT_BIN="$REAL_TIMEOUT" \
    CLAUDE_JSON="$CLAUDE_JSON" \
    LIFE="$LIFE" \
    FRAM_MCP_BIN="$FRAM_MCP_BIN" \
    NORTH_MCP_BIN="$NORTH_MCP_BIN" \
    LINEAR_URL="$LINEAR_URL" \
    WANT_NORTH_PORT="$WANT_NORTH_PORT" \
    MUTATION_TIMEOUT_SECONDS="${MUTATION_TIMEOUT_SECONDS:-2}" \
    HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-2}" \
    CALL_LOG="$CALL_LOG" \
    GET_EXIT="${GET_EXIT:-1}" \
    GET_SLEEP="${GET_SLEEP:-0}" \
    ADD_EXIT="${ADD_EXIT:-0}" \
    REMOVE_EXIT="${REMOVE_EXIT:-0}" \
    "$REPO/scripts/claude-mcp-register.sh" "$@"
}

calls_matching() { grep -c "$1" "$CALL_LOG" 2>/dev/null || true; }
assert_no_match() {
  if grep -Eq "$1" "$CALL_LOG"; then
    printf '%s\n' "$2" >&2
    printf 'unexpected call log:\n' >&2
    sed 's/^/  /' "$CALL_LOG" >&2
    exit 1
  fi
}
assert_match() {
  if ! grep -Eq "$1" "$CALL_LOG"; then
    printf '%s\n' "$2" >&2
    printf 'call log:\n' >&2
    sed 's/^/  /' "$CALL_LOG" >&2
    exit 1
  fi
}

# --- Structural declaration inspection: correct declarations + a FAILING
# health probe must NOT masquerade as a missing declaration. Reconcile issues
# zero health probes and zero destructive mutations.
write_claude_json
GET_EXIT=124 run_register
assert_no_match '^mcp get' \
  'reconcile initiated a health probe to decide declaration presence'
assert_no_match '^mcp remove' \
  'a transient health failure triggered a destructive mcp remove'
assert_no_match '^mcp add' \
  'a transient health failure triggered a re-add of an already-correct declaration'
[ ! -s "$CALL_LOG" ] || {
  printf 'reconcile touched Claude despite correct structural declarations\n' >&2
  exit 1
}

# --- Missing declaration is genuinely added at user scope; healthy peers are
# left untouched.
write_claude_json
"$JQ" 'del(.mcpServers.fram)' "$CLAUDE_JSON" >"$CLAUDE_JSON.tmp"
mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
run_register
assert_match "^mcp add fram -s user -e FRAM_LOG=$WANT_FRAM_LOG -e FRAM_TELEMETRY_LOG=$WANT_FRAM_TELEMETRY_LOG -e FRAM_THREADS=$WANT_FRAM_THREADS -- $FRAM_MCP_BIN$" \
  'a missing fram declaration was not added with the supported user-scope argv'
assert_no_match '^mcp remove fram' \
  'a missing declaration was removed before being added'
assert_no_match '^mcp (add|remove) north' 'a correct north declaration churned'
assert_no_match '^mcp (add|remove) linear' 'a correct linear declaration churned'

# --- A structurally WRONG declaration (drifted command) is removed then
# re-added; the decision is structural, not health-driven.
FRAM_CMD="$SCRATCH/stale-fram-mcp" write_claude_json
GET_EXIT=0 run_register
assert_match '^mcp remove fram -s user$' \
  'a drifted fram declaration was not removed before re-add'
assert_match "^mcp add fram -s user .* -- $FRAM_MCP_BIN$" \
  'a drifted fram declaration was not re-registered at the intended command'

# --- A drifted NORTH_PORT is caught structurally (env value comparison).
NORTH_PORT_VAL="6000" write_claude_json
run_register
assert_match '^mcp add north -s user .* -e NORTH_PORT=7977 -- '"$NORTH_MCP_BIN"'$' \
  'a drifted north env declaration was not reconciled to the intended shape'

# --- Bounded, separate, report-only health: probes every server under a hard
# deadline, surfaces the outcome, mutates nothing, and cannot hang.
write_claude_json
start_ns="$(date +%s%N)"
GET_SLEEP=30 HEALTH_TIMEOUT_SECONDS=1 run_register --health >"$SCRATCH/health.out" 2>&1
elapsed_ms=$((($(date +%s%N) - start_ns) / 1000000))
[ "$elapsed_ms" -lt 8000 ] || {
  printf 'bounded health did not honor its per-probe deadline (%sms)\n' "$elapsed_ms" >&2
  exit 1
}
[ "$(calls_matching '^mcp get fram$')" -eq 1 ]
[ "$(calls_matching '^mcp get north$')" -eq 1 ]
[ "$(calls_matching '^mcp get linear-mcp-msa-new$')" -eq 1 ]
assert_no_match '^mcp add' 'health mode mutated a declaration'
assert_no_match '^mcp remove' 'health mode mutated a declaration'
grep -q 'declaration left intact' "$SCRATCH/health.out"

# --- The script must never read declarations through the health-checking
# list/get surface: its reconcile path inspects ~/.claude.json directly.
if grep -Eq 'mcp (get|list)' <(sed -n '/reconcile_declarations/,/^}/p' \
     "$REPO/scripts/claude-mcp-register.sh"); then
  printf 'reconcile_declarations must not use the health-checking mcp get/list surface\n' >&2
  exit 1
fi

printf 'ok: user-scope MCP declarations are reconciled structurally, health is bounded and separate\n'
