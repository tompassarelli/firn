#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || {
  echo "usage: ${0##*/} NIXOS_SYSTEM_PATH BASELINE_SYSTEM_PATH" >&2
  exit 2
}

system_path=$1
baseline_path=$2
units=$system_path/etc/systemd/system
baseline_units=$baseline_path/etc/systemd/system
marker=/var/lib/north-coord-cutover/bootstrap-complete
legacy_hold=/run/north-coord-legacy-hold

unit() {
  printf '%s/%s\n' "$units" "$1"
}

for name in \
  north-coord.socket \
  north-telemetry-coord.socket \
  north-coord.service \
  north-telemetry-coord.service \
  north-coord-pair.target \
  north-coord-pair-prepare.service \
  north-coord-pair-settle.service \
  north-coord-blue-green.target \
  north-coord-blue-green-resume.service \
  north-coord-blue.service \
  north-telemetry-coord-blue.service \
  north-coord-green.service \
  north-telemetry-coord-green.service \
  north-coord-proxy.service
do
  [[ -f $(unit "$name") ]] || {
    echo "missing unit: $name" >&2
    exit 1
  }
done

# Ordinary activation preserves the permanent listener contract. The sole
# intentional socket delta disables systemd's fatal trigger limit during HOLD;
# PollLimit remains the non-fatal flood throttle.
for name in north-coord.socket north-telemetry-coord.socket; do
  grep -Fxq 'TriggerLimitIntervalSec=0' "$(unit "$name")"
  diff -u \
    <(grep -Fvx 'TriggerLimitIntervalSec=0' "$baseline_units/$name") \
    <(grep -Fvx 'TriggerLimitIntervalSec=0' "$(unit "$name")")
done
cmp "$baseline_units/north-coord-pair.target" \
  "$(unit north-coord-pair.target)"

# Pre-marker reboot starts only the direct graph. Post-marker reboot starts
# only blue/green. All legacy entry points, including pair preparation and
# settlement, are independently gated.
for name in \
  north-coord.service \
  north-telemetry-coord.service \
  north-coord-pair-prepare.service \
  north-coord-pair-settle.service
do
  grep -Fxq "ConditionPathExists=!$marker" "$(unit "$name")"
done
for name in north-coord.service north-telemetry-coord.service; do
  grep -Fxq "ConditionPathExists=!$legacy_hold" "$(unit "$name")"
done
grep -Fxq "ConditionPathExists=$marker" \
  "$(unit north-coord-blue-green.target)"
grep -Fxq "ConditionPathExists=$marker" \
  "$(unit north-coord-blue-green-resume.service)"
grep -Fxq "ConditionPathExists=$marker" \
  "$(unit north-coord-proxy.service)"

# A target condition cannot conditionalize Wants=. Therefore the target is
# never directly wanted at boot. The dependency-light resume oneshot is the
# only boot entrypoint and runs the ordered, idempotent bootstrap command.
if grep -q '^WantedBy=multi-user.target$' \
  "$(unit north-coord-blue-green.target)"; then
  echo "blue/green target is directly wanted at boot" >&2
  exit 1
fi
resume_unit=$(unit north-coord-blue-green-resume.service)
grep -Fxq \
  'Requires=north-coord.socket north-telemetry-coord.socket' \
  "$resume_unit"
grep -Eq '^ExecStart=.*/north-coord-bootstrap$' "$resume_unit"
[[ ! -e "$units/multi-user.target.wants/north-coord-blue-green.target" ]]
[[ -e "$units/multi-user.target.wants/north-coord-blue-green-resume.service" ]]

# The proxy starts after all candidate endpoints but does not Require a
# standby: losing a standby cannot tear down a healthy selected pair.
proxy_unit=$(unit north-coord-proxy.service)
grep -Fxq \
  'Requires=north-coord.socket north-telemetry-coord.socket' \
  "$proxy_unit"
grep -Fxq \
  'Wants=north-coord-blue.service north-telemetry-coord-blue.service north-coord-green.service north-telemetry-coord-green.service' \
  "$proxy_unit"
grep -Fxq 'Sockets=north-coord.socket' "$proxy_unit"
grep -Fxq 'Sockets=north-telemetry-coord.socket' "$proxy_unit"
if grep '^Requires=.*north-coord-blue.service' "$proxy_unit"; then
  echo "proxy incorrectly Requires a private standby" >&2
  exit 1
fi

# The selector parses HAProxy's CSV status with awk during every prestart and
# cutover. Prove the packaged wrapper carries that runtime dependency instead
# of accidentally borrowing it from an interactive host PATH.
selector_prestart=$(
  sed -n 's|^ExecStartPre=\([^ ]*/north-coord-selector\) prestart$|\1|p' \
    "$proxy_unit"
)
[[ -x "$selector_prestart" ]] || {
  echo "proxy selector prestart is not an executable package path" >&2
  exit 1
}
grep -Eq '/nix/store/[a-z0-9]+-gawk-[^/]+/bin' "$selector_prestart" || {
  echo "packaged proxy selector is missing its gawk runtime dependency" >&2
  exit 1
}
selector_prepare=$(
  sed -n 's|^export NORTH_COORD_SELECTOR_PREPARE_COMMAND=||p' \
    "$selector_prestart"
)
[[ -x "$selector_prepare" ]] || {
  echo "selector prepare command is not an executable package path" >&2
  exit 1
}
cutover_gate=$(
  sed -n 's|^exec \([^ ]*/north-coord-cutover-gate\) prepare .*$|\1|p' \
    "$selector_prepare"
)
[[ -x "$cutover_gate" ]] || {
  echo "cutover gate is not an executable package path" >&2
  exit 1
}
jcmd=$(
  sed -n 's|^export NORTH_COORD_JCMD_BIN=||p' "$cutover_gate"
)
[[ "$jcmd" =~ ^/nix/store/[a-z0-9]+-[^/]+/bin/jcmd$ &&
   -x "$jcmd" && ! -L "$jcmd" ]] || {
  echo "cutover gate does not close over one exact packaged jcmd" >&2
  exit 1
}

# All four candidates use the dynamic launcher, have no corpus-level prepare,
# and retain the agreed memory/stop bounds.
for name in north-coord-blue.service north-coord-green.service; do
  path=$(unit "$name")
  slot=${name#north-coord-}
  slot=${slot%.service}
  port=17977
  [[ $slot == green ]] && port=27977
  grep -Eq '^ExecStart=.*/north-coord-slot-start$' "$path"
  grep -Eq '^ExecStartPre=.*/north-coord-(blue|green)-runtime ensure-default$' \
    "$path"
  if grep -q ' prepare$' "$path"; then
    echo "private coordination slot runs forbidden pair prepare: $name" >&2
    exit 1
  fi
  grep -Fxq 'MemoryMax=8G' "$path"
  grep -Fxq 'MemorySwapMax=0' "$path"
  grep -Fxq \
    "Environment=\"JDK_JAVA_OPTIONS=-XX:+UseG1GC -Xmx6g -Xlog:gc:file=/home/tom/.local/state/north/fram-runtime-$slot/gc-$port.log:time,uptime:filecount=3,filesize=10m\"" \
    "$path"
  grep -Fxq 'TimeoutStopSec=15s' "$path"
done
for name in north-telemetry-coord-blue.service north-telemetry-coord-green.service; do
  path=$(unit "$name")
  slot=${name#north-telemetry-coord-}
  slot=${slot%.service}
  port=17978
  [[ $slot == green ]] && port=27978
  grep -Eq '^ExecStart=.*/north-coord-slot-start$' "$path"
  grep -Eq '^ExecStartPre=.*/north-telemetry-coord-(blue|green)-runtime ensure-default$' \
    "$path"
  if grep -q ' prepare$' "$path"; then
    echo "private telemetry slot runs forbidden pair prepare: $name" >&2
    exit 1
  fi
  grep -Fxq 'MemoryMax=6G' "$path"
  grep -Fxq 'MemorySwapMax=0' "$path"
  grep -Fxq \
    "Environment=\"JDK_JAVA_OPTIONS=-XX:+UseG1GC -Xmx4g -Xlog:gc:file=/home/tom/.local/state/north/fram-telemetry-runtime-$slot/gc-$port.log:time,uptime:filecount=3,filesize=10m\"" \
    "$path"
  grep -Fxq 'TimeoutStopSec=15s' "$path"
done

systemd-analyze verify \
  "$(unit north-coord.socket)" \
  "$(unit north-telemetry-coord.socket)" \
  "$(unit north-coord.service)" \
  "$(unit north-telemetry-coord.service)" \
  "$(unit north-coord-pair.target)" \
  "$(unit north-coord-blue-green-resume.service)" \
  "$(unit north-coord-blue-green.target)" \
  "$(unit north-coord-blue.service)" \
  "$(unit north-telemetry-coord-blue.service)" \
  "$(unit north-coord-green.service)" \
  "$(unit north-telemetry-coord-green.service)" \
  "$proxy_unit"

printf 'blue/green systemd graph: PASS\n'
