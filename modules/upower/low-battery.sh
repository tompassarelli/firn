low_battery_decision() {
  local online=$1 status=$2 percent=$3 armed_seconds=$4 limit=8
  [ "$online" = 0 ] || limit=2
  if [ "$status" != Discharging ] || [ "$percent" -gt "$limit" ]; then
    echo clear
  elif [ -n "$armed_seconds" ] && [ "$armed_seconds" -ge 20 ]; then
    echo poweroff
  else
    echo arm
  fi
}

low_battery_run() {
  local root=$1 dir=$2 online percent watts status state last now armed=""
  read -r online percent watts status < <(power_readings "$root")
  [ -n "$status" ] || return 0
  state="charger $([ "$online" = 1 ] && echo connected || echo absent), battery ${status,,}"
  last=$(cat "$dir/state" 2>/dev/null || echo "first reading")
  if [ "$state" != "$last" ]; then
    logger -p daemon.notice -t power-state "$state (was: $last): $percent%, $watts W"
    printf '%s\n' "$state" >"$dir/state"
  fi
  read -r now _ </proc/uptime
  now=${now%.*}
  [ ! -f "$dir/armed" ] || armed=$((now - $(<"$dir/armed")))
  case $(low_battery_decision "$online" "$status" "$percent" "$armed") in
    clear) rm -f "$dir/armed" ;;
    arm) [ -f "$dir/armed" ] || echo "$now" >"$dir/armed" ;;
    poweroff)
      logger -p daemon.warning -t power-state "powering off: $state at $percent%, $watts W, low for $armed s"
      systemctl poweroff
      ;;
  esac
}
