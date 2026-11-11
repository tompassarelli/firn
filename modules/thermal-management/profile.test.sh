#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/../upower/power-readings.sh"
[ ! -f "$here/profile.sh" ] || source "$here/profile.sh"
auto_cpufreq=$(sed -n '/charger = {/,/};/s/.*platform_profile = "\(.*\)";.*/\1/p' "$here/default.nix")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/supplies" "$tmp/state" "$tmp/users/1000/agent-capacity-v1"
echo performance >"$tmp/profile"
failed=0

supply() {
  local name=$1 pair
  shift
  mkdir -p "$tmp/supplies/$name"
  for pair in "$@"; do printf '%s\n' "${pair#*=}" >"$tmp/supplies/$name/${pair%%=*}"; done
}

logger() { printf '%s\n' "${*: -1}" >>"$tmp/journal"; }

supply BAT1 type=Battery capacity=31 power_now=2000000
supply mouse type=Battery scope=Device status=Discharging capacity=1

step() {
  local now=$1 charger=$2 status=$3 hold=$4 want=$5 got
  supply ACAD type=Mains online="$charger"
  supply BAT1 status="$status"
  [ "$hold" = absent ] || printf '{"at":1,"gaming":%s}\n' "$hold" >"$tmp/users/1000/agent-capacity-v1/gaming.json"
  if [ -n "$auto_cpufreq" ]; then
    [ "$charger" = 0 ] || echo "$auto_cpufreq" >"$tmp/profile"
  else
    charger_profile_run "$tmp/supplies" "$tmp/state" "$tmp/profile" "$tmp/users" "$now"
  fi
  got=$(<"$tmp/profile")
  [ "$got" = "$want" ] && return
  printf 'at %s s, charger online=%s, %s, gaming hold %s: got %s, want %s\n' \
    "$now" "$charger" "$status" "$hold" "$got" "$want" >&2
  failed=1
}

step 0 1 Charging false performance
step 10 1 Discharging false performance
step 69 1 Discharging false performance
step 70 1 Discharging false balanced
step 80 1 Charging false balanced
step 100 1 Discharging false balanced
step 110 1 Charging false balanced
step 409 1 Charging false balanced
step 410 1 Charging false performance
step 420 1 Discharging false performance
step 425 1 Charging false performance
step 500 1 Discharging false performance
step 560 1 Discharging false balanced
step 570 1 Full false performance
step 600 1 Discharging false performance
step 660 1 Discharging false balanced
step 670 1 "Not charging" false performance
step 700 1 Discharging true performance
step 800 1 Discharging true performance
step 810 1 Discharging false balanced
step 820 0 Discharging false balanced
step 830 1 Charging false performance
rm -r "$tmp/users/1000"
step 900 1 Discharging absent performance
step 960 1 Discharging absent balanced

switches=$(grep -c '^profile .*: 31%, 2.0 W$' "$tmp/journal" 2>/dev/null || true)
[ "$switches" = 9 ] || {
  printf 'power-state lines: got %s, want 9, one per switch\n' "$switches" >&2
  failed=1
}
exit "$failed"
