iface=${1:-}
action=${2:-}
ac=${SLEEP_DRAIN_AC_ONLINE:-/sys/class/power_supply/ACAD/online}
log() { logger -t sleep-drain -- "$*"; }
[ "$action" = pre-down ] || exit 0
preparing=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager PreparingForSleep 2>/dev/null || echo unknown)
[ "$preparing" = "b true" ] || exit 0
online=$(cat "$ac" 2>/dev/null || echo unknown)
if [ "$online" != 0 ]; then
  log "skip: iface=$iface ac_online=$online"
  exit 0
fi
rc=0
out=$(runuser -u "$DRAIN_USER" -- timeout 4 ssh -o BatchMode=yes -o ConnectTimeout=3 nexus laptop drain sleep 2>&1) || rc=$?
out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)
if [ "$rc" = 0 ]; then
  log "drained: iface=$iface ssh=ok"
else
  log "drain failed (failing open): iface=$iface rc=$rc output=$out"
fi
exit 0
