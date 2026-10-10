#!/usr/bin/env bash
# Deny/pass matrix for the worker tier guard.
set -uo pipefail
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/worker-tier-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/worker-tier-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.json"
printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"worker-tier-guard","kind":"hook","category":"agents","permission":"on","active":true}]}\n' >"$ACTIVATION"

pass=0 fail=0
# run EXPECT DESCRIPTION SUBAGENT_TYPE PROMPT [ENV...]
run() {
  local expect="$1" desc="$2" agent="$3" prompt="$4"; shift 4
  local input out decision ok=0
  input="$(python3 -c 'import json,sys
ti = {"description": "d", "prompt": sys.argv[1]}
if sys.argv[2]: ti["subagent_type"] = sys.argv[2]
print(json.dumps({"tool_name": "Agent", "tool_input": ti}))' "$prompt" "$agent")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVATION="$ACTIVATION" \
    NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 "$@" "$HOOK" 2>&1)"
  decision="$(python3 -c 'import json,sys
try:
    d = json.loads(sys.argv[1] or "null")
except Exception:
    print("malformed"); raise SystemExit
print((d or {}).get("hookSpecificOutput", {}).get("permissionDecision", "silent"))' "${out:-}")"
  case "$expect" in
    deny)  [ "$decision" = deny ] && ok=1 ;;
    allow) [ "$decision" != deny ] && [ "$decision" != malformed ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %-5s  %s\n' "$expect" "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-5s  %s\n      decision=%s out=%s\n' "$expect" "$desc" "$decision" "$out"
  fi
}

MECH=$'Item: rename a field.\nCategory: mechanical\nDone when: check passes.'
DOCS=$'Item: fix a skill line. Category: docs-policy. ETA 5 min.'
FEAT=$'Item: add a parser.\nCategory: feature'
ESC=$'Follows: worker-haiku run a1b2 failed on the check.\nCategory: mechanical'
run deny  'mechanical to worker'        worker        "$MECH"
run deny  'docs-policy to worker'       worker        "$DOCS"
run deny  'mechanical to worker-high'   worker-high   "$MECH"
run allow 'mechanical to worker-haiku'  worker-haiku  "$MECH"
run allow 'docs-policy to worker-haiku' worker-haiku  "$DOCS"
run allow 'mechanical escalated'        worker        "$ESC"
run deny  'worker-high first'           worker-high   "$FEAT"
run deny  'worker-xhigh first'          worker-xhigh  "$FEAT"
run allow 'worker-high escalated'       worker-high   $'Follows: worker run c3 wrong cause twice.\n'"$FEAT"
run allow 'worker-xhigh escalated'      worker-xhigh  $'Follows: worker-high run d4 failed.\n'"$FEAT"
run allow 'feature to worker'           worker        "$FEAT"
run allow 'known facets'                worker        $'Category: tooling. Spec: measured. Scope: one-file.\nSurface: shell. Verify: local-test'
run deny  'unknown facet value'         worker        $'Category: tooling\nSpec: measured\nScope: whole-repo'
run deny  'unknown facet escalated'     worker-high   $'Follows: worker run c3 failed.\nCategory: tooling\nVerify: eyeball'
run allow 'mechanical to Explore'       Explore       "$MECH"
run allow 'mechanical to general'       ''            "$MECH"
run allow 'mechanical to fork'          fork          "$MECH"
run allow 'killswitch'                  worker-high   "$FEAT" AGENT_NO_AUTHORING_HOOKS=1
printf '{"tool_name":"Agent"' | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" "$HOOK" && pass=$((pass + 1))

printf 'worker-tier-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
