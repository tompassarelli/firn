#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/power-readings.sh"
source "$here/low-battery.sh"
upower_action=$(sed -n 's/.*percentageAction = \([0-9]*\);.*/\1/p' "$here/default.nix")
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
failed=0

supply() {
  local name=$1 pair
  shift
  mkdir -p "$root/$name"
  for pair in "$@"; do printf '%s\n' "${pair#*=}" >"$root/$name/${pair%%=*}"; done
}

supply BAT1 type=Battery voltage_now=15117000 current_now=503000
supply mouse type=Battery scope=Device status=Discharging capacity=1
supply ucsi-source-psy-USBC000:001 type=USB scope=System online=0

row() {
  local charger=$1 status=$2 percent=$3 armed=$4 want=$5 online percent_read watts status_read got
  supply ACAD type=Mains online="$charger"
  supply BAT1 status="$status" capacity="$percent"
  read -r online percent_read watts status_read < <(power_readings "$root")
  got=$(low_battery_decision "$online" "$status_read" "$percent_read" "$armed")
  if [ "$want" = clear ] && [ "$status" = Discharging ] && [ "$percent" -le "$upower_action" ]; then
    got="poweroff by UPower at $upower_action%"
  fi
  [ "$got" = "$want" ] && [ "$watts" = 7.6 ] && return
  printf 'charger online=%s, %s at %s%%, low for %ss: got %s (%s W), want %s\n' \
    "$charger" "$status" "$percent" "${armed:--}" "$got" "$watts" "$want" >&2
  failed=1
}

row 0 Discharging 8 "" arm
row 0 Discharging 8 19 arm
row 0 Discharging 8 20 poweroff
row 0 Discharging 9 20 clear
row 0 "Not charging" 5 20 clear
row 1 Discharging 8 20 clear
row 1 Discharging 3 20 clear
row 1 Discharging 2 "" arm
row 1 Discharging 2 20 poweroff
row 1 Charging 1 20 clear
row 0 Charging 1 20 clear
exit "$failed"
