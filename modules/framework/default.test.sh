#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$work/bin/$1"; chmod +x "$work/bin/$1"; }
stub busctl 'printf "b %s\n" "$(cat "$PREPARING")"'
stub runuser 'shift 3; exec "$@"'
stub ssh 'printf "%s\n" "$*" >>"$SSH_LOG"; exit "$(cat "$SSH_RC")"'
stub logger 'shift 3; printf "%s\n" "$*" >>"$LOG"'
export PATH="$work/bin:$PATH" DRAIN_USER=tom SLEEP_DRAIN_AC_ONLINE="$work/ac" PREPARING="$work/preparing" \
  SSH_LOG="$work/ssh.log" SSH_RC="$work/ssh-rc" LOG="$work/log"

drain() {
  printf '%s\n' "$1" >"$work/preparing"
  printf '%s\n' "$2" >"$work/ac"
  printf '%s\n' "${4:-0}" >"$work/ssh-rc"
  : >"$SSH_LOG"
  : >"$LOG"
  bash -euo pipefail "$here/sleep-drain.sh" wlp192s0 "$3"
}

drain true 0 pre-down
grep -qx -- '-o BatchMode=yes -o ConnectTimeout=3 nexus laptop drain sleep' "$SSH_LOG"
grep -qx 'drained: iface=wlp192s0 ssh=ok' "$LOG"

drain false 0 pre-down
[ ! -s "$SSH_LOG" ] || { echo 'a disconnect outside sleep drained the laptop' >&2; exit 1; }

drain true 1 pre-down
[ ! -s "$SSH_LOG" ] || { echo 'a sleep on AC drained the laptop' >&2; exit 1; }
grep -qx 'skip: iface=wlp192s0 ac_online=1' "$LOG"

for action in down up; do
  drain true 0 "$action"
  [ ! -s "$SSH_LOG" ] || { echo "dispatcher action $action drained the laptop" >&2; exit 1; }
done

drain true 0 pre-down 255
grep -qx 'drain failed (failing open): iface=wlp192s0 rc=255 output=' "$LOG"
printf 'ok: sleep-drain drains on battery only while logind prepares for sleep, before the network goes down, and fails open\n'
