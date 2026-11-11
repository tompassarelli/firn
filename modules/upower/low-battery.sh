battery_watts() {
  local microwatts
  if [ -r "$1/power_now" ]; then
    microwatts=$(<"$1/power_now")
  else
    microwatts=$(($(<"$1/voltage_now") * $(<"$1/current_now") / 1000000))
  fi
  microwatts=${microwatts#-}
  printf '%d.%d' $((microwatts / 1000000)) $((microwatts % 1000000 / 100000))
}

power_readings() {
  local supply online=0 status="" percent="" watts=""
  for supply in "$1"/*; do
    [ "$(cat "$supply/scope" 2>/dev/null)" != Device ] || continue
    case $(cat "$supply/type" 2>/dev/null) in
      Mains | USB) [ "$(cat "$supply/online" 2>/dev/null)" != 1 ] || online=1 ;;
      Battery)
        [ -z "$status" ] || continue
        status=$(<"$supply/status")
        percent=$(<"$supply/capacity")
        watts=$(battery_watts "$supply")
        ;;
    esac
  done
  printf '%s %s %s %s\n' "$online" "$percent" "$watts" "$status"
}

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
