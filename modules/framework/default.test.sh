#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$work/bin/$1"; chmod +x "$work/bin/$1"; }
stub busctl 'printf "b %s\n" "$(cat "$PREPARING")"'
stub systemctl 'printf "%s\n" "$*" >>"$SYSTEMCTL_LOG"; exit "$(cat "$SYSTEMCTL_RC")"'
stub logger 'shift 3; printf "%s\n" "$*" >>"$LOG"'
export PATH="$work/bin:$PATH" DRAIN_USER=tom PREPARING="$work/preparing" \
  SYSTEMCTL_LOG="$work/systemctl.log" SYSTEMCTL_RC="$work/systemctl-rc" LOG="$work/log"

dispatch() {
  printf '%s\n' "$1" >"$work/preparing"
  printf '%s\n' "${3:-0}" >"$work/systemctl-rc"
  : >"$SYSTEMCTL_LOG"
  : >"$LOG"
  bash -euo pipefail "$here/sleep-drain.sh" wlp192s0 "$2"
}
untouched() { [ ! -s "$SYSTEMCTL_LOG" ] || { echo "$1 ran a placement tick" >&2; exit 1; }; }

dispatch true pre-down
grep -qx -- '--user -M tom@ restart laptop-auto.service' "$SYSTEMCTL_LOG"
grep -qx 'drain: iface=wlp192s0 tick=ok' "$LOG"

dispatch false pre-down
untouched 'a disconnect outside sleep'

dispatch false up
grep -qx -- '--user -M tom@ restart --no-block laptop-auto.service' "$SYSTEMCTL_LOG"
grep -qx 'reopen: iface=wlp192s0 tick=ok' "$LOG"

for action in down dhcp4-change; do
  dispatch true "$action"
  untouched "dispatcher action $action"
done

dispatch true pre-down 1
grep -qx 'drain failed (failing open): iface=wlp192s0 rc=1 output=' "$LOG"
printf 'ok: sleep-drain ticks placement before the network goes down for sleep and again when it comes back up, and fails open\n'
