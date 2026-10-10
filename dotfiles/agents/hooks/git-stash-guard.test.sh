#!/usr/bin/env bash
# Adversarial matrix for the stash guard, incl. the false-positive
# trap: a commit MESSAGE or heredoc body that mentions the trigger phrase
# must still be ALLOWED — only a command-position invocation is denied.
set -uo pipefail
# Hooks run with the managed hook runtime first on PATH; so do their tests.
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/git-stash-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/git-stash-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.active"

pass=0 fail=0
set_active() {
  if [ "$1" = true ]; then printf 'hook git-stash-guard\n' >"$ACTIVATION"; else : >"$ACTIVATION"; fi
}
set_active true

# run EXPECT DESCRIPTION COMMAND [ENV...]
run() {
  local expect="$1" desc="$2" cmd="$3"; shift 3
  local input out decision ok=0
  input="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVE="$ACTIVATION" \
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
    printf 'FAIL  %-5s  %s\n      cmd=%q\n      decision=%s out=%s\n' "$expect" "$desc" "$cmd" "$decision" "$out"
  fi
}

echo '== unsafe stash invocations are denied =='
run deny 'bare git stash' 'git stash'
run deny 'git stash push without -m' 'git stash push'
run deny 'git stash push -u without -m' 'git stash push -u'
run deny 'git stash save without -m' 'git stash save'
run deny 'git stash -u without -m' 'git stash -u'
run deny 'git stash pop' 'git stash pop'
run deny 'git stash pop ref' 'git stash pop stash@{0}'
run deny 'git -C dir stash' 'git -C /tmp/x stash'
run deny 'stash behind sudo' 'sudo git stash'
run deny 'stash after separator' 'printf ready && git stash'
run deny 'stash on next line' "$(printf 'printf ready\ngit stash pop')"
run deny 'stash in brace group' '{ git stash; }'

echo '== safe stash forms remain allowed =='
run allow 'git stash list' 'git stash list'
run allow 'git stash show' 'git stash show stash@{0}'
run allow 'git stash apply ref' 'git stash apply 1a2b3c4d'
run allow 'git stash drop ref' 'git stash drop stash@{1}'
run allow 'git stash push -m TAG' 'git stash push -m tag-1'
run allow 'git stash push -u -m TAG' 'git stash push -u -m "my tag"'
run allow 'git stash save -m TAG' 'git stash save -m tag'
run allow 'git stash push --message=TAG' 'git stash push --message=tag'

echo '== mentions in messages, heredocs and prose are not invocations =='
run allow 'message mentions git stash pop' 'git commit -m "stop using git stash pop"'
run allow 'heredoc body mentions git stash' "$(cat <<'EOF2'
git commit -F - <<'MSG'
Replace git stash and git stash pop with WIP commits.
MSG
EOF2
)"
run allow 'quoted prose' "echo 'git stash'"

echo '== kill-switch =='
run allow 'guards off via env' 'git stash' AGENT_NO_AUTHORING_HOOKS=1
set_active false
run allow 'UnitId off via activation' 'git stash'
set_active true
run deny 'UnitId back on via activation' 'git stash'

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
