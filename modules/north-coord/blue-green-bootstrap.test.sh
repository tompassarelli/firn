#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/systemd/active" "$scratch/systemd/masked"

cat >"$scratch/bin/systemctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root=$NORTH_COORD_TEST_SYSTEMD
command=$1
shift

active() {
  : >"$root/active/$1"
  if [[ "$1" == north-coord-pair.target ]]; then
    : >"$root/active/north-coord.service"
    : >"$root/active/north-telemetry-coord.service"
  fi
}

inactive() {
  rm -f -- "$root/active/$1"
}

case "$command" in
  is-active)
    [[ "$1" == --quiet ]] && shift
    [[ -e "$root/active/$1" ]]
    ;;
  start)
    for unit in "$@"; do
      [[ ! -e "$root/masked/$unit" ]]
      active "$unit"
    done
    ;;
  stop)
    for unit in "$@"; do
      inactive "$unit"
    done
    ;;
  mask)
    [[ "$1" == --runtime ]] && shift
    for unit in "$@"; do : >"$root/masked/$unit"; done
    ;;
  unmask)
    [[ "$1" == --runtime ]] && shift
    for unit in "$@"; do rm -f -- "$root/masked/$unit"; done
    ;;
  show)
    [[ "$1" == --property=MainPID && "$2" == --value ]]
    unit=$3
    if [[ ! -e "$root/active/$unit" ]]; then
      echo 0
    else
      case "$unit" in
        north-coord.service) echo 900000001 ;;
        north-telemetry-coord.service) echo 900000002 ;;
        north-coord-blue.service) echo 900000003 ;;
        north-telemetry-coord-blue.service) echo 900000004 ;;
        north-coord-green.service) echo 900000005 ;;
        north-telemetry-coord-green.service) echo 900000006 ;;
        *) echo 900000099 ;;
      esac
    fi
    ;;
  *) echo "unsupported fake systemctl command: $command $*" >&2; exit 2 ;;
esac
SH
chmod 0700 "$scratch/bin/systemctl"

cat >"$scratch/gate" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NORTH_COORD_TEST_GATE_LOG"
if [[ "${NORTH_COORD_TEST_FAIL_VERIFY:-0}" -eq 1 &&
      "$1" == verify ]]; then
  exit 1
fi
SH
cat >"$scratch/selector" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NORTH_COORD_TEST_SELECTOR_LOG"
SH
chmod 0700 "$scratch/gate" "$scratch/selector"

touch \
  "$scratch/systemd/active/north-coord.socket" \
  "$scratch/systemd/active/north-telemetry-coord.socket" \
  "$scratch/systemd/active/north-coord-pair.target" \
  "$scratch/systemd/active/north-coord.service" \
  "$scratch/systemd/active/north-telemetry-coord.service"

coord_log=$scratch/coordination.log
telemetry_log=$scratch/telemetry.log
printf 'coordination\n' >"$coord_log"
printf 'telemetry\n' >"$telemetry_log"
state=$scratch/cutover

run_bootstrap() {
  sudo -n env \
    PATH="$scratch/bin:$PATH" \
    NORTH_COORD_CUTOVER_USER="$(id -un)" \
    NORTH_COORD_CUTOVER_GROUP="$(id -gn)" \
    NORTH_COORD_CUTOVER_STATE="$state" \
    NORTH_COORD_CUTOVER_TOKEN_FILE="$state/cutover.token" \
    NORTH_COORD_SELECTOR_MAP="$state/route.map" \
    NORTH_COORD_BOOTSTRAP_MARKER="$state/bootstrap-complete" \
    NORTH_COORD_CUTOVER_GATE="$scratch/gate" \
    NORTH_COORD_SELECTOR="$scratch/selector" \
    NORTH_COORD_COORD_LOG="$coord_log" \
    NORTH_COORD_TELEMETRY_LOG="$telemetry_log" \
    NORTH_COORD_TEST_SYSTEMD="$scratch/systemd" \
    NORTH_COORD_TEST_GATE_LOG="$scratch/gate.log" \
    NORTH_COORD_TEST_SELECTOR_LOG="$scratch/selector.log" \
    NORTH_COORD_TEST_FAIL_VERIFY="${NORTH_COORD_TEST_FAIL_VERIFY:-0}" \
      "$here/north-coord-bootstrap" "$@"
}

# One bounded migration: public sockets remain active, legacy target retires,
# selected pair/proxy start, and the shared token is owner-only.
run_bootstrap
[[ -f "$state/bootstrap-complete" ]]
grep -Fxq 'active blue' "$state/route.map"
[[ $(stat -Lc '%a' "$state/cutover.token") == 600 ]]
[[ -e "$scratch/systemd/active/north-coord.socket" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord.socket" ]]
[[ -e "$scratch/systemd/active/north-coord-proxy.service" ]]
[[ -e "$scratch/systemd/active/north-coord-blue.service" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord-blue.service" ]]
[[ -e "$scratch/systemd/active/north-coord-green.service" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord-green.service" ]]
[[ ! -e "$scratch/systemd/active/north-coord.service" ]]
[[ ! -e "$scratch/systemd/active/north-telemetry-coord.service" ]]

# Idempotent resume starts/verifies candidates before proxy.
run_bootstrap

# Explicit operator rollback restores the complete legacy target graph and
# removes the durable blue/green activation state without closing sockets.
run_bootstrap rollback-legacy
[[ ! -e "$state/bootstrap-complete" ]]
[[ ! -e "$state/route.map" ]]
[[ -e "$scratch/systemd/active/north-coord-pair.target" ]]
[[ -e "$scratch/systemd/active/north-coord.service" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord.service" ]]
[[ ! -e "$scratch/systemd/active/north-coord-proxy.service" ]]
[[ ! -e "$scratch/systemd/active/north-coord-blue.service" ]]
[[ ! -e "$scratch/systemd/active/north-coord-green.service" ]]
[[ -e "$scratch/systemd/active/north-coord.socket" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord.socket" ]]

# A failed active-authority proof after HOLD automatically restores the legacy
# pair and leaves no route/bootstrap marker.
export NORTH_COORD_TEST_FAIL_VERIFY=1
if run_bootstrap; then
  echo "bootstrap unexpectedly succeeded with failed authority proof" >&2
  exit 1
fi
unset NORTH_COORD_TEST_FAIL_VERIFY
[[ ! -e "$state/bootstrap-complete" ]]
[[ ! -e "$state/route.map" ]]
[[ -e "$scratch/systemd/active/north-coord.service" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord.service" ]]

printf 'blue/green bootstrap + rollback behavior: PASS\n'
