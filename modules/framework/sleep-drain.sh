iface=${1:-}
action=${2:-}
log() { logger -t sleep-drain -- "$*"; }
tick() { timeout 4 systemctl --user -M "$DRAIN_USER@" restart "$@" laptop-auto.service 2>&1; }
rc=0
case "$action" in
  pre-down)
    preparing=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager PreparingForSleep 2>/dev/null || echo unknown)
    [ "$preparing" = "b true" ] || exit 0
    out=$(tick) || rc=$?
    verb=drain
    ;;
  up)
    out=$(tick --no-block) || rc=$?
    verb=reopen
    ;;
  *) exit 0 ;;
esac
out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)
if [ "$rc" = 0 ]; then
  log "$verb: iface=$iface tick=ok"
else
  log "$verb failed (failing open): iface=$iface rc=$rc output=$out"
fi
exit 0
