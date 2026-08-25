#!/usr/bin/env bash
# Adversarial matrix for the blind-staging guard, incl. the false-positive
# trap: a commit MESSAGE or heredoc body that mentions the trigger phrase
# must still be ALLOWED — only a command-position invocation is denied.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/git-blind-stage-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/git-blind-stage-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.json"

pass=0 fail=0
set_active() {
  printf '{"schema":"north.agent-activation/v1","units":[{"id":"git-blind-stage-guard","kind":"hook","category":"authoring","active":%s}]}\n' "$1" >"$ACTIVATION"
}
set_active true

# run EXPECT DESCRIPTION COMMAND [ENV...]
run() {
  local expect="$1" desc="$2" cmd="$3"; shift 3
  local input out decision ok=0
  input="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVATION="$ACTIVATION" "$@" "$HOOK" 2>&1)"
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
    printf 'FAIL  %-5s  %s\n      cmd=%q\n      decision=%s out=%s\n' "$expect" "$desc" "$cmd" "$decision" "$out"
  fi
}

echo '== bare blind-staging invocations are denied =='
run deny 'bare git add -A' 'git add -A'
run deny 'bare git add --all' 'git add --all'
run deny 'bare git add -u' 'git add -u'
run deny 'bare git add --update' 'git add --update'
run deny 'bare git add .' 'git add .'
run deny 'git commit -a' 'git commit -a'
run deny 'git commit --all' 'git commit --all'
run deny 'git commit -am short cluster' 'git commit -am "msg"'
run deny 'git add -A behind sudo' 'sudo git add -A'
run deny 'git add -A after separator' 'printf ready && git add -A'
run deny 'git add -A on next line' "$(printf 'printf ready\ngit add -A')"
run deny 'git add -A in brace group' '{ git add -A; }'

echo '== enumerated / scoped staging remains allowed =='
run allow 'enumerated path' 'git add path/to/file'
run allow 'enumerated relative path' 'git add ./path/to/file'
run allow 'enumerated multiple paths' 'git add path/one.txt path/two.txt'
run allow 'commit without -a' 'git commit -m "msg"'
run allow 'add with dotted extension, not bare dot' 'git add .gitignore'

echo '== the false-positive trap: MESSAGE/body mentions are never invocations =='
run allow 'message mentions git add -A' 'git commit -m "fix: stop using git add -A here"'
run allow 'message mentions git commit -a' 'git commit -m "note: git commit -a is now blocked"'
run allow 'heredoc body mentions the phrase' "$(cat <<'EOF'
git commit -F - <<'MSG'
This commit fixes the earlier git add -A mistake and git commit -a misuse.
MSG
EOF
)"
run allow 'single-quoted example is prose' "echo 'git add -A'"
run allow 'double-quoted example is prose' 'echo "git add -A is dangerous"'

echo '== kill-switch =='
run allow 'guards off via env' 'git add -A' AGENT_NO_AUTHORING_HOOKS=1
set_active false
run allow 'UnitId off via activation' 'git add -A'
set_active true
run deny 'UnitId back on via activation' 'git add -A'

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
