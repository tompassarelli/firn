#!/usr/bin/env bash
# Focused two-direction fixture: dangerous virtual-root and repository-container
# search shapes deny; bounded metadata and checkout-scoped search pass.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_GUARD="$HERE/resource-safe-search-guard.sh"
NORTH_REPO="${AGENT_CONFIG_NORTH_REPO:?set AGENT_CONFIG_NORTH_REPO to the exact North candidate under test}"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/resource-safe-search-guard.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
PROVIDER_HOOKS="$SCRATCH/provider-hooks"
ACTIVATION="$SCRATCH/activation.json"
CONTAINER="$SCRATCH/project"
CODE="$CONTAINER/main"
LANE="$CONTAINER/worktrees/lane"
PYTHON="${NORTH_AGENT_PYTHON:-/etc/codex/hooks/runtime/python3}"
[ -x "$PYTHON" ] || {
  printf 'missing sealed hook Python runtime: %s\n' "$PYTHON" >&2
  exit 1
}
mkdir -p "$PROVIDER_HOOKS/lib" "$CODE/src" "$LANE/src"
: >"$CODE/src/main.txt"
: >"$LANE/src/main.txt"

for source in authoring-killswitch.sh harness-dial.sh; do
  candidate="$NORTH_REPO/agent-runtime/hooks/lib/$source"
  [ -r "$candidate" ] || {
    printf 'missing candidate North hook helper: %s\n' "$candidate" >&2
    exit 1
  }
  ln -s "$candidate" "$PROVIDER_HOOKS/lib/$source"
done
ln -s "$SOURCE_GUARD" "$PROVIDER_HOOKS/resource-safe-search-guard.sh"
GUARD="$PROVIDER_HOOKS/resource-safe-search-guard.sh"

set_active() {
  printf '{"schema":"north.agent-activation/v1","units":[{"id":"resource-safe-search-guard","kind":"hook","category":"authoring","active":%s}]}\n' \
    "$1" >"$ACTIVATION"
}
set_active true

payload() {
  "$PYTHON" - "$1" "${2:-$CODE}" <<'PY'
import json
import sys
print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "cwd": sys.argv[2],
    "tool_input": {"command": sys.argv[1]},
}))
PY
}

decision() {
  "$PYTHON" -c 'import json,sys
try:
    value=json.loads(sys.argv[1] or "null")
except Exception:
    print("malformed")
else:
    print((value or {}).get("hookSpecificOutput", {}).get("permissionDecision", "allow"))' "$1"
}

pass=0 fail=0
run_case() {
  local expect="$1" description="$2" command="$3" cwd="${4:-$CODE}" output observed ok=0
  shift $(( $# >= 4 ? 4 : 3 ))
  output="$(payload "$command" "$cwd" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVATION="$ACTIVATION" \
    NORTH_AGENT_PYTHON="$PYTHON" \
    "$@" "$GUARD" 2>&1)"
  observed="$(decision "$output")"
  case "$expect" in
    deny-virtual)
      [ "$observed" = deny ] && [[ "$output" == *'ps -eo pid=,comm=,args='* ]] \
        && [[ "$output" == *'readlink -e /proc/PID/cwd'* ]] && ok=1
      ;;
    deny-container)
      [ "$observed" = deny ] && [[ "$output" == *'exact checkout or subtree'* ]] \
        && [[ "$output" == *"$CONTAINER/main"* ]] && ok=1
      ;;
    allow) [ "$observed" = allow ] && ok=1 ;;
  esac
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1)); printf 'PASS %-5s %s\n' "$expect" "$description"
  else
    fail=$((fail + 1)); printf 'FAIL %-5s %s: observed=%s output=%s\n' \
      "$expect" "$description" "$observed" "$output" >&2
  fi
}

echo '== dangerous direction =='
run_case deny-virtual 'reported proc cwd glob' 'rg -l -z TARGET /proc/[0-9]*/cwd'
run_case deny-virtual 'expanded many proc cwd operands' 'rg -l TARGET /proc/1/cwd /proc/2/cwd'
run_case deny-virtual 'brace-expanded proc cwd operands' 'rg TARGET /proc/{1,2}/cwd'
run_case deny-virtual 'proc fd fan-out' 'ripgrep TARGET /proc/*/fd/*'
run_case deny-virtual 'proc root recursion' 'rg TARGET /proc'
run_case deny-virtual 'sys root recursion' 'ripgrep TARGET /sys'
run_case deny-virtual 'recursive grep over dev' 'grep -R TARGET /dev'
run_case deny-virtual 'fd traversal over run' 'fd TARGET /run'
run_case deny-virtual 'runtime alias traversal' 'rg TARGET /var/run'
run_case deny-virtual 'lock alias traversal' 'rg TARGET /var/lock'
run_case deny-virtual 'cwd supplies virtual root' 'rg TARGET' /proc
run_case deny-virtual 'nested shell payload is decoded' "bash -lc 'rg TARGET /proc/[0-9]*/cwd'"
run_case deny-container 'cwd repository-container rg files sweep' 'rg --files' "$CONTAINER"
run_case deny-container 'explicit repository-container rg files sweep' "rg --files $CONTAINER"
run_case deny-container 'explicit repository-container content search' "rg TARGET $CONTAINER"
run_case deny-container 'recursive grep over repository container' "grep -R TARGET $CONTAINER"

echo '== sanctioned and adjacent direction =='
run_case allow 'ordinary scoped code rg' "rg TARGET $CODE"
run_case allow 'ordinary cwd-scoped code rg' 'rg TARGET' "$CODE"
run_case allow 'files inside exact main checkout' "rg --files $CODE"
run_case allow 'files inside exact worktree checkout' "rg --files $LANE"
run_case allow 'content inside exact subtree' "rg TARGET $CODE/src"
run_case allow 'content in one exact file' "rg TARGET $CODE/src/main.txt"
run_case allow 'informational rg does not search container cwd' 'rg --version' "$CONTAINER"
run_case allow 'virtual root in pattern only' "rg '/proc/[0-9]*/cwd' $CODE"
run_case allow 'one known proc metadata file' 'rg Name /proc/self/status'
run_case allow 'nonrecursive grep of one proc file' 'grep Name /proc/self/status'
run_case allow 'select process metadata with ps' 'ps -eo pid=,comm=,args='
run_case allow 'read one selected cwd edge' 'readlink -e /proc/1/cwd'
run_case allow 'read one selected scalar field' 'cat /proc/1/cmdline'
run_case allow 'quoted mention is not invocation' "echo 'rg TARGET /proc/[0-9]*/cwd'"
run_case allow 'commit message mention is not invocation' "git commit -m 'avoid rg /proc'"
run_case allow 'heredoc mention is not invocation' $'cat <<EOF\nrg TARGET /proc\nEOF'

echo '== activity and fail-open direction =='
set_active false
run_case allow 'inactive catalog row disables guard' 'rg TARGET /proc'
run_case deny-virtual 'force-live zero overrides inactive row' 'rg TARGET /proc' "$CODE" \
  AGENT_NO_AUTHORING_HOOKS=0
set_active true
run_case allow 'session off switch disables guard' 'rg TARGET /proc' "$CODE" \
  AGENT_NO_AUTHORING_HOOKS=1
printf 'not-json\n' >"$ACTIVATION"
run_case allow 'malformed activation fails open' 'rg TARGET /proc'
set_active true

malformed_output="$(printf 'not-json' | env -u AGENT_NO_AUTHORING_HOOKS \
  NORTH_AGENT_ACTIVATION="$ACTIVATION" NORTH_AGENT_PYTHON="$PYTHON" "$GUARD" 2>&1)"
if [ "$(decision "$malformed_output")" = allow ]; then
  pass=$((pass + 1)); printf 'PASS allow malformed payload fails open\n'
else
  fail=$((fail + 1)); printf 'FAIL allow malformed payload: %s\n' "$malformed_output" >&2
fi

oversized="$("$PYTHON" - <<'PY'
import json
print(json.dumps({"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"rg x /proc " + "x" * 1048576}}))
PY
)"
oversized_output="$(printf '%s' "$oversized" | env -u AGENT_NO_AUTHORING_HOOKS \
  NORTH_AGENT_ACTIVATION="$ACTIVATION" NORTH_AGENT_PYTHON="$PYTHON" "$GUARD" 2>&1)"
if [ "$(decision "$oversized_output")" = allow ]; then
  pass=$((pass + 1)); printf 'PASS allow oversized payload fails open\n'
else
  fail=$((fail + 1)); printf 'FAIL allow oversized payload: %s\n' "$oversized_output" >&2
fi

printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
