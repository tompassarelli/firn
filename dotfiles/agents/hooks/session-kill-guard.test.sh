#!/usr/bin/env bash
# Adversarial matrix for session-killing and unmanaged-child launch shapes.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/session-kill-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/session-kill-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.json"

pass=0 fail=0 LAST_OUT=""
set_active() {
  printf '{"schema":"north.agent-activation/v1","units":[{"id":"session-kill-guard","kind":"hook","category":"authoring","active":%s}]}\n' "$1" >"$ACTIVATION"
}
set_active true

# run EXPECT DESCRIPTION COMMAND [ENV...]
run() {
  local expect="$1" desc="$2" cmd="$3"; shift 3
  local input out decision ok=0
  input="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" NORTH_AGENT_ACTIVATION="$ACTIVATION" "$@" "$HOOK" 2>&1)"
  LAST_OUT="$out"
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

echo '== broadcast kill is denied =='
run deny 'kill -9 -1' 'kill -9 -1'
run deny 'kill -TERM -1' 'kill -TERM -1'
run deny 'kill -s TERM -1' 'kill -s TERM -1'
run deny 'kill -- -1' 'kill -- -1'
run deny 'bare kill -1 (no pid)' 'kill -1'
run deny 'behind sudo' 'sudo kill -9 -1'
run deny 'after separator' 'printf ready && kill -9 -1'
run deny 'on a second line' "$(printf 'printf ready\nkill -9 -1')"
run deny 'in brace group' '{ kill -9 -1; }'

echo '== user-wide sweeps are denied =='
run deny 'pkill -u user' 'pkill -u tom'
run deny 'pkill -U uid' 'pkill -U 1000'
run deny 'pkill -TERM -u user' 'pkill -TERM -u tom'
run deny 'killall -u user' 'killall -u tom'

echo '== compositor / session teardown is denied =='
run deny 'pkill niri' 'pkill niri'
run deny 'pkill -f niri' 'pkill -f niri'
run deny 'killall niri' 'killall niri'
run deny 'loginctl terminate-user' 'loginctl terminate-user tom'
run deny 'loginctl kill-session' 'loginctl kill-session 3'
run deny 'systemctl --user exit' 'systemctl --user exit'
run deny 'systemctl --user stop niri' 'systemctl --user stop niri.service'
run deny 'systemctl --user restart graphical-session' 'systemctl --user restart graphical-session.target'
run deny 'systemctl stop user@' 'sudo systemctl stop user@1000.service'

echo '== unmanaged agent-child launch shapes are denied =='
run deny 'nohup at command position' 'nohup bun /tmp/wake-cljs-migrate.mjs &'
run deny 'setsid at command position' 'setsid node /tmp/wake-cljs-migrate.mjs'
run deny 'disown at command position' 'sleep 1; disown'
run deny 'ordinary background job' 'bun task &'
run deny 'direct Bun /tmp script' 'bun /tmp/wake-cljs-migrate.mjs'
run deny 'direct Node /tmp script' 'node --enable-source-maps /tmp/wake-cljs-migrate.ts'
case "$LAST_OUT" in
  *'run-bounded <duration> -- <command>'*'24h maximum'*'transient cgroup plus PID namespace'*'48G hard ceiling'*)
    pass=$((pass + 1)); echo 'PASS  deny   ownership denial names the bounded compliant move' ;;
  *)
    fail=$((fail + 1)); printf 'FAIL  deny   ownership denial is incomplete (got: %s)\n' "$LAST_OUT" ;;
esac

echo '== scoped signals — the sanctioned alternative — stay allowed =='
run allow 'kill by pid' 'kill 1234'
run allow 'kill -9 by pid' 'kill -9 1234'
run allow 'kill -TERM by pid' 'kill -TERM 1234'
run allow 'SIGHUP to a pid (kill -1 <pid>)' 'kill -1 1234'
run allow 'scoped process group' 'kill -TERM -- -12345'
run allow 'job spec' 'kill %1'
run allow 'kill -l listing' 'kill -l'
run allow 'pkill with unique pattern' 'pkill -f "wrangler dev --port 8788"'
run allow 'pkill -u with pattern is scoped' 'pkill -u tom -f my-dev-server'
run allow 'killall by name' 'killall node'
run allow 'loginctl read-only' 'loginctl list-sessions'
run allow 'systemctl --user status niri' 'systemctl --user status niri.service'
run allow 'systemctl --user restart other unit' 'systemctl --user restart wob.service'
run allow 'systemctl stop a system unit' 'sudo systemctl stop nginx.service'
run allow 'run-bounded owns a background controller' 'run-bounded 30m -- command &'
run allow 'run-bounded owns a temporary Bun script' 'run-bounded 30m -- bun /tmp/wake-cljs-migrate.mjs'
run allow 'foreground ordinary command' 'bun task'
run allow 'ordinary node source outside /tmp' 'node sdk/task.ts'
run allow '&& is not a background operator' 'printf ready && bun task'
run allow 'redirect ampersand is not a background operator' 'bun task > /tmp/task.log 2>&1'

echo '== prose mentions are never invocations =='
run allow 'commit message mentions kill -9 -1' 'git commit -m "guard: refuse kill -9 -1 broadcast"'
run allow 'echo single-quoted' "echo 'kill -9 -1'"
run allow 'echo double-quoted' 'echo "never run pkill -u tom"'
run allow 'quoted detached-command prose' 'echo "nohup bun /tmp/wake-cljs-migrate.mjs &"'
run allow 'heredoc body mentions the phrase' "$(cat <<'EOF'
cat > notes.md <<'MSG'
The incident command was kill -9 -1 via a bare supervisor run.
MSG
EOF
)"
run allow 'heredoc child command is prose' "$(cat <<'EOF'
cat > notes.md <<'MSG'
nohup bun /tmp/wake-cljs-migrate.mjs &
MSG
EOF
)"

echo '== kill-switch =='
run allow 'guards off via env' 'kill -9 -1' AGENT_NO_AUTHORING_HOOKS=1
set_active false
run allow 'UnitId off via activation' 'kill -9 -1'
set_active true
run deny 'UnitId back on via activation' 'kill -9 -1'

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
