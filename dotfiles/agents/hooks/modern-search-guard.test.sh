#!/usr/bin/env bash
# Two-direction fixture: recursive grep and find tree searches deny with the
# exact rg/fd replacement; filters, named files, shallow finds, git grep and
# mentions in quoted text or heredocs pass.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_GUARD="$HERE/modern-search-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/modern-search-guard.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
export AGENT_HOOK_ERRORS="$SCRATCH/errors.tsv"
PROVIDER_HOOKS="$SCRATCH/provider-hooks"
ACTIVATION="$SCRATCH/activation.active"
CODE="$SCRATCH/code"
PYTHON="${NORTH_AGENT_PYTHON:-/etc/codex/hooks/runtime/python3}"
[ -x "$PYTHON" ] || {
  printf 'missing sealed hook Python runtime: %s\n' "$PYTHON" >&2
  exit 1
}
mkdir -p "$PROVIDER_HOOKS/lib" "$CODE/src"
: >"$CODE/a.ts"
: >"$CODE/b.ts"

for source in authoring-killswitch.sh north-agent-activation.sh; do
  candidate="$HERE/../lib/$source"
  [ -r "$candidate" ] || {
    printf 'missing Firn-owned hook helper: %s\n' "$candidate" >&2
    exit 1
  }
  ln -s "$candidate" "$PROVIDER_HOOKS/lib/$source"
done
ln -s "$SOURCE_GUARD" "$PROVIDER_HOOKS/modern-search-guard.sh"
GUARD="$PROVIDER_HOOKS/modern-search-guard.sh"

set_active() {
  if [ "$1" = true ]; then printf 'hook modern-search-guard\n' >"$ACTIVATION"; else : >"$ACTIVATION"; fi
}
set_active true

payload() {
  "$PYTHON" -c 'import json,sys
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
    "$1" "${2:-$CODE}"
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
record() { # ok description detail
  if [ "$1" -eq 1 ]; then
    pass=$((pass + 1)); printf 'PASS %s\n' "$2"
  else
    fail=$((fail + 1)); printf 'FAIL %s: %s\n' "$2" "$3" >&2
  fi
}

run() { # command [env...]
  local command="$1"
  shift
  payload "$command" | env -u AGENT_NO_AUTHORING_HOOKS HOME="$SCRATCH/home" \
    NORTH_AGENT_ACTIVE="$ACTIVATION" NORTH_AGENT_PYTHON="$PYTHON" \
    "$@" "$GUARD" 2>&1
}

# deny: the refusal must name this exact replacement and the tool defaults.
deny() { # command replacement
  local output ok=0
  output="$(run "$1")"
  [ "$(decision "$output")" = deny ] && [[ "$output" == *"\`$2\`"* ]] \
    && [[ "$output" == *ast-grep* ]] && [[ "$output" == *'jq/yq'* ]] && ok=1
  record "$ok" "deny  $1 -> $2" "$output"
}

allow() { # command [env...]
  local output ok=0
  output="$(run "$@")"
  [ "$(decision "$output")" = allow ] && ok=1
  record "$ok" "allow $1" "$output"
}

echo '== grep -r becomes rg =='
deny 'grep -rn foo src' 'rg -n foo src'
deny 'grep -rn foo .' 'rg -n foo .'
deny 'grep -R foo' 'rg -L foo'
deny 'grep --recursive -il foo src lib' 'rg -il foo src lib'
deny "grep -rn --include='*.ts' foo src" "rg -n -g '*.ts' foo src"
deny 'grep -r --exclude-dir=node_modules -A 3 foo .' "rg -g '!node_modules' -A 3 foo ."
deny 'grep -rnE "a|b" src' "rg -n 'a|b' src"
deny 'grep -rl -e foo -e bar src' 'rg -l -e foo -e bar src'
deny 'egrep -r foo src' 'rg foo src'
deny 'rgrep foo src' 'rg foo src'
deny 'cd src && grep -rn foo .' 'rg -n foo .'
deny 'grep -rn foo src | head -5' 'rg -n foo src'
deny 'cat f | grep -r foo' 'rg foo'
deny 'sudo grep -rn foo /etc' 'rg -n foo /etc'
deny "bash -c 'grep -rn foo src'" 'rg -n foo src'
deny 'x=$(grep -rl foo src)' 'rg -l foo src'
deny '(grep -rn foo src)' 'rg -n foo src'

echo '== find tree searches become fd =='
deny "find . -name '*.ts'" 'fd -e ts'
deny "find src -type f -name '*.ts'" 'fd -t f -e ts . src'
deny 'find . -type d' 'fd -t d'
deny 'find src -type f' 'fd -t f . src'
deny "find . -iname 'readme*'" "fd -i -g 'readme*'"
deny 'find . -name Cargo.toml' 'fd -g Cargo.toml'
deny "find . -name '.env*'" "fd -H -g '.env*'"
deny "find . -maxdepth 3 -name '*.nix'" 'fd -e nix -d 3'
deny "find . \\( -name '*.ts' -o -name '*.tsx' \\)" 'fd -e ts -e tsx'
deny "find . -name '*.ts' -o -name '*.tsx'" 'fd -e ts -e tsx'
deny "find . -path '*/test/*' -type f" "fd -p -t f -g '**/test/**'"
deny "find src -path '*/x/*.ts'" "fd -p -g '**/x/**/*.ts' src"
allow "find . -path './src/*'"
allow "find . -path '*test*'"
deny "find . -name '*.log' -exec wc -l {} +" 'fd -e log -X wc -l'
deny "find . -name '*.sh' -exec chmod +x {} \\;" 'fd -e sh -x chmod +x {}'
deny "find . -type f -print0 | xargs -0 wc -l" 'fd -t f -0'
deny "find . -name '*.ts' | wc -l" 'fd -e ts'

echo '== filters, named files, shallow finds and git grep stay allowed =='
allow 'cat f | grep foo'
allow 'ps aux | grep -v grep | grep node'
allow 'grep foo a.ts b.ts'
allow 'grep -n foo a.ts'
allow 'grep -rn foo a.ts b.ts'
allow 'git grep foo'
allow 'git grep -n foo -- src'
allow 'find . -maxdepth 1 -type f'
allow "find src -maxdepth 1 -name '*.ts'"
allow 'find . -mindepth 1 -maxdepth 0'
allow 'find src'
allow 'find . -print'
allow "find . -name '*.tmp' -delete"
allow 'find . -type f -mtime -1'
allow "find . -path ./node_modules -prune -o -name '*.js' -print"
allow "find . ! -name '*.ts'"
allow "find . -name '*.go' -printf '%p\\n'"
allow "find . -type f -name '*.ts' -o -name '*.tsx'"
allow 'rg -n foo src'
allow 'fd -e ts'
allow 'zgrep foo log.gz'

echo '== a mention is not an invocation =='
allow "git commit -m 'replace grep -rn foo src with rg'"
allow "git commit -m \"stop running find . -name '*.ts'\""
allow "echo 'grep -r foo .'"
allow $'cat <<EOF\ngrep -rn foo src\nfind . -name \'*.ts\'\nEOF'
allow $'git commit -F - <<\'EOF\'\nUse rg, not grep -r; fd, not find . -type f.\nEOF'
allow 'rg "grep -r" docs'

echo '== activity and fail-open =='
set_active false
allow 'grep -rn foo src'
output="$(run 'grep -rn foo src' AGENT_NO_AUTHORING_HOOKS=0)"
ok=0; [ "$(decision "$output")" = deny ] && ok=1
record "$ok" 'force-live zero overrides an inactive row' "$output"
set_active true
allow 'grep -rn foo src' AGENT_NO_AUTHORING_HOOKS=1
printf 'not-json\n' >"$ACTIVATION"
allow 'grep -rn foo src'
set_active true

output="$(printf 'not-json' | env -u AGENT_NO_AUTHORING_HOOKS \
  NORTH_AGENT_ACTIVE="$ACTIVATION" NORTH_AGENT_PYTHON="$PYTHON" "$GUARD" 2>&1)"
ok=0; [ "$(decision "$output")" = allow ] && ok=1
record "$ok" 'malformed payload fails open' "$output"

output="$("$PYTHON" -c 'import json
print(json.dumps({"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"grep -r x . " + "x" * 1048576}}))' |
  env -u AGENT_NO_AUTHORING_HOOKS NORTH_AGENT_ACTIVE="$ACTIVATION" \
    NORTH_AGENT_PYTHON="$PYTHON" "$GUARD" 2>&1)"
ok=0; [ "$(decision "$output")" = allow ] && ok=1
record "$ok" 'oversized payload fails open' "$output"

output="$("$PYTHON" -c 'import json
print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"grep -r find"}}))' |
  env -u AGENT_NO_AUTHORING_HOOKS NORTH_AGENT_ACTIVE="$ACTIVATION" \
    NORTH_AGENT_PYTHON="$PYTHON" "$GUARD" 2>&1)"
ok=0; [ "$(decision "$output")" = allow ] && ok=1
record "$ok" 'an Edit envelope is not a search' "$output"

printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
