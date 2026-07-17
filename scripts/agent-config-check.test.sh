#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_native_identity() {
  local manifest="$1" expected_provider="$2" label="$3"
  local expected_spawn="AGENT_PROVIDER=$expected_provider /home/tom/code/north/bin/north-on-spawn"
  local expected_repair="AGENT_PROVIDER=$expected_provider /home/tom/code/north/bin/north-on-tooluse"
  local event command spawn_count=0 repair_count=0

  while IFS=$'\t' read -r event command; do
    [ -n "$command" ] || continue
    case "$command" in
      *'/north-on-spawn')
        spawn_count=$((spawn_count + 1))
        case "$event" in SessionStart|SubagentStart) ;; *)
          printf 'unexpected %s north-on-spawn event: %s\n' "$label" "$event" >&2
          exit 1
        esac
        [ "$command" = "$expected_spawn" ] || {
          printf '%s %s has wrong spawn provider identity: %s\n' "$label" "$event" "$command" >&2
          exit 1
        }
        ;;
      *'/north-on-tooluse')
        repair_count=$((repair_count + 1))
        [ "$event" = PostToolUse ] || {
          printf 'unexpected %s north-on-tooluse event: %s\n' "$label" "$event" >&2
          exit 1
        }
        [ "$command" = "$expected_repair" ] || {
          printf '%s %s has wrong repair provider identity: %s\n' "$label" "$event" "$command" >&2
          exit 1
        }
        ;;
    esac
  done < <(jq -r '.hooks | to_entries[] | .key as $event | .value[] | .hooks[]? | select(.type == "command" and ((.command | contains("/north-on-spawn")) or (.command | contains("/north-on-tooluse")))) | [$event,.command] | @tsv' "$manifest")

  [ "$spawn_count" -eq 2 ] || {
    printf '%s has %s north-on-spawn bindings, expected 2\n' "$label" "$spawn_count" >&2
    exit 1
  }
  [ "$repair_count" -eq 1 ] || {
    printf '%s has %s north-on-tooluse bindings, expected 1\n' "$label" "$repair_count" >&2
    exit 1
  }
  jq -e '[.hooks | to_entries[] | .value[] | .hooks[]? | select(.type == "command" and (.command | startswith("AGENT_PROVIDER=")) and ((.command | test("/north-on-(spawn|tooluse)$")) | not))] | length == 0' "$manifest" >/dev/null
}

assert_native_identity "$REPO/dotfiles/claude/settings.json" anthropic Claude
assert_native_identity "$REPO/dotfiles/codex/hooks.json" openai Codex
"$REPO/scripts/agent-config-check.sh" >/dev/null

# A deterministic route probe is diagnostic evidence, not provider preference.
# The compact harness report must summarize the allocation policy itself.
if grep -Fq '.diagnosticRouteProbe' "$REPO/scripts/agent-config-check.sh"; then
  printf 'agent-config-check must not present diagnosticRouteProbe as routing policy\n' >&2
  exit 1
fi
grep -Fq '"Allocation  ' \
  "$REPO/scripts/agent-config-check.sh"
grep -Fq 'North providers JSON v2' \
  "$REPO/scripts/agent-config-check.sh"
grep -Fq 'timeout 30 claude plugin list --json' \
  "$REPO/scripts/agent-config-check.sh"
grep -Fq 'held at committed' \
  "$REPO/scripts/agent-config-check.sh"
if grep -Fq 'claude plugin list --json 2>&1' \
  "$REPO/scripts/agent-config-check.sh"; then
  printf 'plugin stderr must not be merged into the JSON document\n' >&2
  exit 1
fi

# Off-main HEAD is excluded from plugin reconciliation. A cache matching main is
# held; a cache matching only the feature HEAD is deferred, never declared
# current and never promoted to hard drift while the checkout is ineligible.
source "$REPO/scripts/agent-config-check.sh"
main_full='1111111111111111111111111111111111111111'
feature_full='2222222222222222222222222222222222222222'
classify_gaffer_cache "${main_full:0:12}" "$feature_full" "$main_full" feature ''
[ "$GAFFER_CACHE_STATE" = held-off-main ]
classify_gaffer_cache "${feature_full:0:12}" "$feature_full" "$main_full" feature ''
[ "$GAFFER_CACHE_STATE" = deferred-off-main ]
classify_gaffer_cache "${feature_full:0:12}" "$feature_full" '' feature 'dirty'
[ "$GAFFER_CACHE_STATE" = deferred-no-main-ref ]

# Repository/CI mode validates canonical declarations against this checkout,
# not whether Tom's absolute live path happens to exist. A failing readlink shim
# simulates a relocated checkout; only --local may require live resolution.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-relocation.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$scratch/bin/readlink"
chmod +x "$scratch/bin/readlink"
PATH="$scratch/bin:$PATH" "$REPO/scripts/agent-config-check.sh" >/dev/null

printf 'ok: native identity is adapter-pinned and North reports allocation policy, not a diagnostic route probe\n'
