#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
watchdog=$script_dir/north-watchdog
status=$script_dir/north-watchdog-status
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

fake_systemctl() {
  case ${1:-} in
    show) printf '%s\n' 42 ;;
    restart) printf '%s\n' "${2:-}" >>"$case_dir/restarts" ;;
    *) return 1 ;;
  esac
}

fake_nc() {
  printf '%s\n' "$*" >"$case_dir/nc.args"
  command cat >"$case_dir/request"
  if [[ -e $case_dir/fail ]]; then
    return 1
  fi
  printf '{:version-free true}\n'
}

fake_timeout() {
  [[ ${1:-} == 3s ]] || return 1
  shift
  "$@"
}

fake_date() {
  case ${1:-} in
    +%s) cat "$case_dir/epoch" ;;
    +%s%3N)
      local value
      value=$(<"$case_dir/milliseconds")
      printf '%s\n' "$((value + 7))" >"$case_dir/milliseconds"
      printf '%s\n' "$value"
      ;;
    *) return 1 ;;
  esac
}

case ${0##*/} in
  systemctl) fake_systemctl "$@"; exit ;;
  nc) fake_nc "$@"; exit ;;
  timeout) fake_timeout "$@"; exit ;;
  date) fake_date "$@"; exit ;;
esac

new_case() {
  export case_dir=$scratch/$1
  mkdir -p "$case_dir/bin" "$case_dir/state" "$case_dir/proc/42"
  : >"$case_dir/restarts"
  printf '%s\n' 1785598200 >"$case_dir/epoch"
  printf '%s\n' 1785598200000 >"$case_dir/milliseconds"
  printf '%s\n' 'active blue' >"$case_dir/route.map"
  printf 'VmRSS:\t12345 kB\n' >"$case_dir/proc/42/status"
  for command in systemctl nc timeout date; do
    ln -s "$script_dir/default.test.sh" "$case_dir/bin/$command"
  done
}

run_watchdog() {
  NORTH_WATCHDOG_STATE_DIR=$case_dir/state \
  NORTH_WATCHDOG_ROUTE_MAP=$case_dir/route.map \
  NORTH_WATCHDOG_LOG_FILE=$case_dir/probe.log \
  NORTH_WATCHDOG_PROC_ROOT=$case_dir/proc \
  NORTH_WATCHDOG_DATE=$case_dir/bin/date \
  NORTH_WATCHDOG_NC=$case_dir/bin/nc \
  NORTH_WATCHDOG_SYSTEMCTL=$case_dir/bin/systemctl \
  NORTH_WATCHDOG_TIMEOUT=$case_dir/bin/timeout \
  "$watchdog"
}

assert_line() {
  grep -Fxq -- "$2" "$1" || {
    printf 'missing line %s in %s\n' "$2" "$1" >&2
    cat "$1" >&2
    exit 1
  }
}

new_case successful_probe
run_watchdog
assert_line "$case_dir/probe.log" '1785598200 blue 7 ok 12345'
assert_line "$case_dir/request" '{:op :for-log :expected-log "/home/tom/.local/state/north/coordination.log" :request {:op :version-free}}'
assert_line "$case_dir/nc.args" '-N 127.0.0.1 17977'

new_case green_route
printf '%s\n' 'active green' >"$case_dir/route.map"
run_watchdog
assert_line "$case_dir/probe.log" '1785598200 green 7 ok 12345'
assert_line "$case_dir/nc.args" '-N 127.0.0.1 27977'

new_case restart_and_cooldown
touch "$case_dir/fail"
run_watchdog
run_watchdog
run_watchdog
run_watchdog
[[ $(wc -l <"$case_dir/restarts") == 1 ]]
assert_line "$case_dir/restarts" 'north-coord-blue.service'
assert_line "$case_dir/probe.log" 'RESTART 1785598200 blue three_consecutive_failures ok'

printf '%s\n' 1785598801 >"$case_dir/epoch"
run_watchdog
run_watchdog
[[ $(wc -l <"$case_dir/restarts") == 2 ]]

new_case status_output
now=$(date +%s)
today=$(date --date='today 00:00' +%s)
{
  printf '%s blue 40 ok 100\n' "$((now - 7200))"
  printf '%s green 30 fail 200\n' "$((now - 1800))"
  printf '%s green 20 ok 210\n' "$((now - 60))"
  printf 'RESTART %s green three_consecutive_failures ok\n' "$today"
} >"$case_dir/probe.log"
NORTH_WATCHDOG_LOG_FILE=$case_dir/probe.log "$status" >"$case_dir/status"
assert_line "$case_dir/status" 'Success 1h:  50.0% (1/2)'
assert_line "$case_dir/status" 'Success 24h: 66.7% (2/3)'
assert_line "$case_dir/status" 'Current latency: 20 ms'
assert_line "$case_dir/status" 'Restarts today: 1'
assert_line "$case_dir/status" 'Last restart reason: three_consecutive_failures'

new_case truncation
printf '%100s' x >"$case_dir/probe.log"
NORTH_WATCHDOG_MAX_LOG_BYTES=100 run_watchdog
[[ $(wc -l <"$case_dir/probe.log") == 1 ]]
assert_line "$case_dir/probe.log" '1785598200 blue 7 ok 12345'

printf 'PASS: north watchdog runtime and status tests\n'
