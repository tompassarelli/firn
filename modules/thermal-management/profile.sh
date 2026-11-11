charger_profile_decision() {
  local online=$1 status=$2 hold=$3 drained=$4 seconds=$5
  if [ "$online" != 1 ]; then
    echo leave
  elif [ "$hold" = 1 ]; then
    echo performance
  elif [ "$status" = Discharging ] && { [ "$drained" = 1 ] || [ "$seconds" -ge 60 ]; }; then
    echo balanced
  elif [ "$status" = Charging ] && [ "$drained" = 1 ] && [ "$seconds" -lt 300 ]; then
    echo balanced
  else
    echo performance
  fi
}

gaming_hold() {
  local marker
  for marker in "$1"/*/agent-capacity-v1/gaming.json; do
    [ "$(jq -r .gaming "$marker" 2>/dev/null)" != true ] || {
      echo 1
      return
    }
  done
  echo 0
}

charger_profile_run() {
  local root=$1 dir=$2 profile=$3 users=$4 now=$5
  local online percent watts status since last hold drained=0 seconds want was
  read -r online percent watts status < <(power_readings "$root")
  [ -n "$status" ] || return 0
  IFS=$'\t' read -r since last 2>/dev/null <"$dir/status" || last=""
  if [ "$status" != "$last" ]; then
    since=$now
    printf '%s\t%s\n' "$since" "$status" >"$dir/status"
  fi
  seconds=$((now - since))
  [ ! -e "$dir/drained" ] || drained=1
  hold=$(gaming_hold "$users")
  want=$(charger_profile_decision "$online" "$status" "$hold" "$drained" "$seconds")
  if [ "$want" = balanced ]; then touch "$dir/drained"; else rm -f "$dir/drained"; fi
  was=$(<"$profile")
  if [ "$want" = leave ] || [ "$want" = "$was" ]; then return 0; fi
  echo "$want" >"$profile"
  logger -p daemon.notice -t power-state \
    "profile $want (was: $was): charger connected, battery ${status,,} for $seconds s, gaming hold $([ "$hold" = 1 ] && echo on || echo off): $percent%, $watts W"
}
