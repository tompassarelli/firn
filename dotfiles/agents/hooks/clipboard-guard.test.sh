#!/usr/bin/env bash
# Adversarial matrix for the clipboard guard: command-position clipboard writes
# and niri screenshot actions are denied; reads, agent-capture and mentions
# in quotes or heredocs are allowed.
set -uo pipefail
# Hooks run with the managed hook runtime first on PATH; so do their tests.
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/clipboard-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/clipboard-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.active"

pass=0 fail=0
set_active() {
  if [ "$1" = true ]; then printf 'hook clipboard-guard\n' >"$ACTIVATION"; else : >"$ACTIVATION"; fi
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

echo '== clipboard writes are denied =='
run deny 'bare wl-copy' 'printf x | wl-copy'
run deny 'wl-copy --clear' 'wl-copy --clear'
run deny 'wl-copy image' 'wl-copy -t image/png < shot.png'
run deny 'pathed wl-copy' '/run/current-system/sw/bin/wl-copy hi'
run deny 'wl-copy after separator' 'ls && wl-copy hi'
run deny 'wl-copy behind env' 'env FOO=1 wl-copy hi'
run deny 'niri screenshot-window' 'niri msg action screenshot-window --id 82 --write-to-disk true'
run deny 'niri screenshot-screen' 'niri msg action screenshot-screen'
run deny 'niri screenshot ui' 'niri msg action screenshot'
run deny 'niri json screenshot' 'niri msg -j action screenshot-window'
run deny 'niri screenshot in substitution' 'x=$(niri msg action screenshot-window); echo $x'

echo '== reads, sanctioned capture and other niri actions are allowed =='
run allow 'wl-paste list' 'wl-paste --list-types'
run allow 'agent-capture screen' 'agent-capture --screen /tmp/s.png'
run allow 'grim' 'grim /tmp/s.png'
run allow 'niri focus' 'niri msg action focus-window --id 3'
run allow 'niri windows' 'niri msg -j windows'
run allow 'help text' 'niri msg action --help | grep screenshot'

echo '== mentions in messages, heredocs and prose are not invocations =='
run allow 'commit message' 'git commit -m "agents must not run wl-copy"'
run allow 'quoted prose' "echo 'niri msg action screenshot-window'"
run allow 'heredoc body' "$(printf 'cat <<EOF2\nwl-copy hi\nEOF2')"

echo '== kill-switch =='
run allow 'guards off via env' 'wl-copy hi' AGENT_NO_AUTHORING_HOOKS=1
set_active false
run allow 'UnitId off via activation' 'wl-copy hi'
set_active true
run deny 'UnitId back on via activation' 'wl-copy hi'

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
