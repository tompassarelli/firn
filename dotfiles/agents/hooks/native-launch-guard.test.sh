#!/usr/bin/env bash
# Deny/pass matrix for the native client launch guard. Mentions, reads and
# self-wrapping routes pass; only an unwrapped launch at command position
# is denied.
set -uo pipefail
# Hooks run with the managed hook runtime first on PATH; so do their tests.
export PATH="/etc/codex/hooks/runtime:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/native-launch-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/native-launch-guard-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
mkdir -p "$SCRATCH/home/.local/state/north"
ACTIVATION="$SCRATCH/activation.json"

pass=0 fail=0
set_active() {
  local permission=off
  [ "$1" = true ] && permission=on
  printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"native-launch-guard","kind":"hook","category":"authoring","permission":"%s","active":%s}]}\n' "$permission" "$1" >"$ACTIVATION"
}
set_active true

# run EXPECT DESCRIPTION COMMAND [ENV...]
run() {
  local expect="$1" desc="$2" cmd="$3"; shift 3
  local input out decision ok=0
  input="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
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
    printf 'FAIL  %-5s  %s\n      cmd=%q\n      decision=%s out=%s\n' "$expect" "$desc" "$cmd" "$decision" "$out"
  fi
}

MC='bun /opt/skills/machine-capacity/scripts/machine-capacity.mjs'
EXE='"$HOME/.local/share/wisp/online/clone-d/pfx/drive_c/Program Files (x86)/Warcraft III/_retail_/x86_64/Warcraft III.exe"'
echo '== unwrapped launches are denied =='
run deny 'wine Warcraft III.exe' "wine $EXE -launch"
run deny 'WINEPREFIX=... wine64' "WINEPREFIX=\$HOME/p wine64 $EXE"
run deny 'proton waitforexitandrun' "STEAM_COMPAT_DATA_PATH=/x \$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-7-x86_64/proton waitforexitandrun $EXE"
run deny 'env -i ... steam-run chain' "env -i HOME=/home/tom dbus-run-session -- steam-run env A=1 proton run $EXE"
run deny 'exe run directly' "$EXE -launch"
run deny 'after separator' "cd /tmp && timeout 60 wine $EXE"
run deny 'run-scope wrapper is not native' "$MC run --class moderate --owner x --timeout-seconds 60 -- wine $EXE"
echo '== wrapped, self-wrapping and read-only forms pass =='
run allow 'native session wraps wine' "$MC session --class native --owner wisp-x -- wine $EXE"
run allow 'native session wraps steam-run chain' "$MC session --class native --memory-gib 1.5 --owner c -- env -i HOME=/home/tom dbus-run-session -- steam-run env proton run $EXE"
run allow 'wisp lan pool' 'bun wisp lan pool --pairs 1'
run allow 'launch.sh self-wraps' '~/.local/share/wisp/online/launch.sh d /run/user/1000/private-desktop.x'
run allow 'pgrep mentions exe' "pgrep -f 'Warcraft III.exe'"
run allow 'ls exe' 'ls ~/x/*.exe'
run allow 'echo mentions wine' "echo 'run wine Warcraft III.exe'"
run allow 'heredoc body mentions wine' "$(printf 'cat <<EOF >notes.txt\nwine %s\nEOF' "$EXE")"
run allow 'commit message' 'git commit -m "wine steam-run proton notes"'
echo '== malformed and kill-switch =='
run allow 'unbalanced quote fails open' "wine 'unterminated"
run allow 'guards off via env' "wine $EXE" AGENT_NO_AUTHORING_HOOKS=1
set_active false
run allow 'UnitId off via activation' "wine $EXE"
set_active true
run deny 'UnitId back on via activation' "wine $EXE"

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
