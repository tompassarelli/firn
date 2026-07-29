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
command=$1
slot=$2
case "$command" in
  verify) phase=active ;;
  verify-phase) phase=$3 ;;
  *) echo "unsupported fake gate command: $*" >&2; exit 2 ;;
esac

key=$slot:$phase
counter=$NORTH_COORD_TEST_READINESS_STATE/${slot}.${phase}.attempts
attempt=0
[[ ! -f "$counter" ]] || read -r attempt <"$counter"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" >"$counter"
chmod 0644 "$counter"

delay=0
case "$key" in
  blue:standby) delay=${NORTH_COORD_TEST_DELAY_BLUE_STANDBY_ATTEMPTS:-0} ;;
  blue:active) delay=${NORTH_COORD_TEST_DELAY_BLUE_ACTIVE_ATTEMPTS:-0} ;;
  green:standby) delay=${NORTH_COORD_TEST_DELAY_GREEN_STANDBY_ATTEMPTS:-0} ;;
esac
if (( attempt <= delay )); then
  printf '%s is still folding (attempt %s)\n' "$key" "$attempt" >&2
  exit 1
fi
if [[ "${NORTH_COORD_TEST_NEVER_READY:-}" == "$key" ]]; then
  printf '%s never became ready\n' "$key" >&2
  exit 1
fi
if [[ "${NORTH_COORD_TEST_FAIL_VERIFY:-0}" -eq 1 &&
      "$phase" == active ]]; then
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
mkdir -p "$scratch/readiness"

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
    NORTH_COORD_BOOTSTRAP_READY_TIMEOUT_SECONDS="${NORTH_COORD_BOOTSTRAP_READY_TIMEOUT_SECONDS:-8}" \
    NORTH_COORD_BOOTSTRAP_READY_INTERVAL_SECONDS=1 \
    NORTH_COORD_TEST_SYSTEMD="$scratch/systemd" \
    NORTH_COORD_TEST_GATE_LOG="$scratch/gate.log" \
    NORTH_COORD_TEST_SELECTOR_LOG="$scratch/selector.log" \
    NORTH_COORD_TEST_READINESS_STATE="$scratch/readiness" \
    NORTH_COORD_TEST_DELAY_BLUE_STANDBY_ATTEMPTS="${NORTH_COORD_TEST_DELAY_BLUE_STANDBY_ATTEMPTS:-0}" \
    NORTH_COORD_TEST_DELAY_BLUE_ACTIVE_ATTEMPTS="${NORTH_COORD_TEST_DELAY_BLUE_ACTIVE_ATTEMPTS:-0}" \
    NORTH_COORD_TEST_DELAY_GREEN_STANDBY_ATTEMPTS="${NORTH_COORD_TEST_DELAY_GREEN_STANDBY_ATTEMPTS:-0}" \
    NORTH_COORD_TEST_NEVER_READY="${NORTH_COORD_TEST_NEVER_READY:-}" \
    NORTH_COORD_TEST_FAIL_VERIFY="${NORTH_COORD_TEST_FAIL_VERIFY:-0}" \
      "$here/north-coord-bootstrap" "$@"
}

# One bounded migration: public sockets remain active, legacy target retires,
# selected pair/proxy start, and the shared token is owner-only. Type=simple
# marks each private JVM active before its fold completes, so prove that every
# post-start authority check waits for delayed readiness.
export NORTH_COORD_TEST_DELAY_BLUE_STANDBY_ATTEMPTS=2
export NORTH_COORD_TEST_DELAY_BLUE_ACTIVE_ATTEMPTS=1
export NORTH_COORD_TEST_DELAY_GREEN_STANDBY_ATTEMPTS=2
run_bootstrap
unset NORTH_COORD_TEST_DELAY_BLUE_STANDBY_ATTEMPTS
unset NORTH_COORD_TEST_DELAY_BLUE_ACTIVE_ATTEMPTS
unset NORTH_COORD_TEST_DELAY_GREEN_STANDBY_ATTEMPTS
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
[[ $(<"$scratch/readiness/blue.standby.attempts") -ge 3 ]]
[[ $(<"$scratch/readiness/blue.active.attempts") -ge 2 ]]
[[ $(<"$scratch/readiness/green.standby.attempts") -ge 3 ]]

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

# A pair that never becomes active after HOLD exhausts the explicit readiness
# budget and automatically restores both legacy writers. This is the live
# failure boundary: no proxy or durable route may survive.
export NORTH_COORD_TEST_NEVER_READY=blue:active
export NORTH_COORD_BOOTSTRAP_READY_TIMEOUT_SECONDS=1
if run_bootstrap; then
  echo "bootstrap unexpectedly succeeded with a never-ready active pair" >&2
  exit 1
fi
unset NORTH_COORD_TEST_NEVER_READY
unset NORTH_COORD_BOOTSTRAP_READY_TIMEOUT_SECONDS
[[ ! -e "$state/bootstrap-complete" ]]
[[ ! -e "$state/route.map" ]]
[[ -e "$scratch/systemd/active/north-coord.service" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord.service" ]]
[[ ! -e "$scratch/systemd/active/north-coord-proxy.service" ]]

# A failed active-authority proof after HOLD automatically restores the legacy
# pair and leaves no route/bootstrap marker.
export NORTH_COORD_TEST_FAIL_VERIFY=1
export NORTH_COORD_BOOTSTRAP_READY_TIMEOUT_SECONDS=1
if run_bootstrap; then
  echo "bootstrap unexpectedly succeeded with failed authority proof" >&2
  exit 1
fi
unset NORTH_COORD_TEST_FAIL_VERIFY
unset NORTH_COORD_BOOTSTRAP_READY_TIMEOUT_SECONDS
[[ ! -e "$state/bootstrap-complete" ]]
[[ ! -e "$state/route.map" ]]
[[ -e "$scratch/systemd/active/north-coord.service" ]]
[[ -e "$scratch/systemd/active/north-telemetry-coord.service" ]]

printf 'blue/green bootstrap + rollback behavior: PASS\n'
