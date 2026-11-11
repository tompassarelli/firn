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
