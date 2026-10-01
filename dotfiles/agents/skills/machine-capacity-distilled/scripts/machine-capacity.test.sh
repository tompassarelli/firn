#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/machine-capacity-test.XXXXXX")
fixture_pids=()
cleanup() {
  for pid in "${fixture_pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  for pid in "${fixture_pids[@]}"; do wait "$pid" 2>/dev/null || true; done
  rm -rf "${scratch:?}"
}
trap cleanup EXIT
user_runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

"$here/build-machine-capacity" "$scratch/machine-capacity.mjs"
cmp -- "$here/machine-capacity.mjs" "$scratch/machine-capacity.mjs"

fixture() {
  bun "$scratch/machine-capacity.mjs" fixture \
    --class "${1}" \
    --cores 24 \
    --memory-total-mib 96343 \
    --memory-available-mib "${2}" \
    --cpu-some-avg10-basis-points "${3}" \
    --memory-full-avg10-basis-points "${4}" \
    --leased-cpus "${5}" \
    --leased-memory-mib "${6}" "${@:7}" | jq -c 'del(.leasedCpuCeilings,.aggregateCpuLimit)'
}

[[ $(fixture heavy 70000 500 0 6 8192) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":0}' ]]
[[ $(fixture exclusive 70000 500 0 0 0) == '{"decision":"RUN","class":"exclusive","cpus":18,"memoryMiB":16384,"memoryFullAvg10":0}' ]]
[[ $(fixture heavy 70000 2000 394 0 0 || true) == '{"decision":"DEFER_CPU_PRESSURE","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 21000 0 394 0 0 || true) == '{"decision":"DEFER_MEMORY_HEADROOM","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 70000 0 394 15 8192) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 70000 0 394 0 70000 || true) == '{"decision":"DEFER_MEMORY_CAPACITY","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture agent 73412 0 394 8 9728) == '{"decision":"RUN","class":"agent","cpus":0,"memoryMiB":768,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 73412 0 394 8 9728) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 73412 0 10000 8 9728) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":100}' ]]

# Low pressure admits useful work even when peer ceilings already total 18 CPUs.
[[ $(fixture heavy 80000 0 0 18 21504 --peer-runs 3 | jq -r '.decision') == RUN ]]
[[ $(fixture exclusive 80000 0 0 4 3072 | jq -r '.decision') == RUN ]]
[[ $(fixture exclusive 80000 0 0 2 2048 --peer-runs 1 || true) == *'"decision":"DEFER_EXCLUSIVE"'* ]]
[[ $(fixture moderate 80000 0 0 18 16384 --peer-runs 1 --peer-exclusive-runs 1 || true) == *'"decision":"DEFER_EXCLUSIVE"'* ]]
[[ $(fixture heavy 80000 0 0 6 8192 --peer-runs 1 --unbounded-runs 1 || true) == *'"decision":"DEFER_UNBOUNDED_PEER"'* ]]

fixture_runtime="$scratch/runtime"
mkdir -p "$fixture_runtime"
ln -s "$user_runtime_dir/systemd" "$fixture_runtime/systemd"
reservation=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" reserve \
  --class agent --owner fixture:/capacity --timeout-seconds 5)
lease=$(jq -r '.lease' <<<"$reservation")
[[ $lease =~ ^[0-9a-f-]{36}$ ]]
renewed=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" renew \
  --lease "$lease" --owner fixture:/capacity --timeout-seconds 5)
[[ $(jq -r '.decision' <<<"$renewed") == RENEWED ]]
released=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" release \
  --lease "$lease" --owner fixture:/capacity)
[[ $(jq -r '.decision' <<<"$released") == RELEASED ]]

rejected_runtime="$scratch/rejected-runtime"
set +e
rejected=$(XDG_RUNTIME_DIR="$rejected_runtime" bun "$scratch/machine-capacity.mjs" reserve \
  --class heavy --owner fixture:/capacity --timeout-seconds 5 2>&1)
rejected_status=$?
set -e
[[ $rejected_status -eq 2 ]]
[[ $rejected == 'machine-capacity: reserve --class must be agent' ]]
[[ ! -e "$rejected_runtime/agent-capacity-v1" ]]

expiring=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" reserve \
  --class agent --owner fixture:/capacity --timeout-seconds 1)
[[ $(jq -r '.decision' <<<"$expiring") == RESERVED ]]
sleep 1.1
reclaimed=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent)
[[ $(jq -r '.reclaimed' <<<"$reclaimed") == 1 ]]

sleeper_pid_file="$scratch/sleeper.pid"
set +e
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
  --class heavy \
  --owner fixture:/capacity \
  --timeout-seconds 1 \
  -- bash -c 'sleep 60 & child=$!; printf "%s\n" "$child" >"$1"; wait "$child"' \
  fixture-scope "$sleeper_pid_file"
scope_status=$?
set -e
[[ $scope_status -ne 0 ]]
read -r sleeper_pid <"$sleeper_pid_file"
[[ $sleeper_pid =~ ^[1-9][0-9]*$ ]]
! kill -0 "$sleeper_pid" 2>/dev/null

# Four sleeping jobs request 24 CPU ceilings on this 24-core fixture host.
# Their kernel ancestor, not those ceilings, enforces the shared 18-CPU cap.
for number in 1 2 3 4; do
  XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
    --class heavy --owner fixture:/capacity --timeout-seconds 30 \
    -- bash -c 'IFS=: read -r _ _ group < /proc/self/cgroup; printf "%s\n" "$group" >"$1"; sleep 60 & wait' \
    fixture-scope "$scratch/group-$number" >"$scratch/out-$number" 2>"$scratch/err-$number" &
  fixture_pids+=("$!")
done
for number in 1 2 3 4; do
  for attempt in {1..100}; do
    [[ -s "$scratch/group-$number" ]] && break
    sleep 0.05
  done
  [[ -s "$scratch/group-$number" ]]
  read -r group <"$scratch/group-$number"
  parent=${group%/*}
  [[ $parent == */agent-capacity.slice ]]
  read -r quota period <"/sys/fs/cgroup$parent/cpu.max"
  [[ $quota != max ]]
  cores=$(getconf _NPROCESSORS_ONLN)
  [[ $((quota * 4)) -eq $((period * cores * 3)) ]]
  read -r quota period <"/sys/fs/cgroup$group/cpu.max"
  [[ $((quota / period)) -eq 6 ]]
  [[ $(cat "/sys/fs/cgroup$group/memory.high") -eq $((8192 * 1024 * 1024)) ]]
done
probe=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class exclusive || true)
[[ $(jq -r '.reason' <<<"$probe") == DEFER_EXCLUSIVE ]]
[[ $(jq -r '.leasedCpuCeilings' <<<"$probe") -eq 24 ]]
[[ $(jq -r '.aggregateCpuLimit' <<<"$probe") -eq 18 ]]
for pid in "${fixture_pids[@]}"; do kill -TERM "$pid"; done
for pid in "${fixture_pids[@]}"; do wait "$pid" || true; done
fixture_pids=()
for number in 1 2 3 4; do
  [[ $(tail -n 1 "$scratch/err-$number" | jq -r '.decision') == RELEASED ]]
  read -r group <"$scratch/group-$number"
  [[ ! -e "/sys/fs/cgroup$group" ]]
done
[[ $(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class exclusive | jq -r '.decision') == RUN ]]

# An agent allowance does not block its exclusive command, which then blocks peers.
reservation=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" reserve \
  --class agent --owner fixture:/capacity --timeout-seconds 30)
lease=$(jq -r '.lease' <<<"$reservation")
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
  --class exclusive --owner fixture:/capacity --timeout-seconds 30 \
  -- bash -c 'printf ready >"$1"; sleep 60 & wait' fixture-exclusive "$scratch/exclusive-ready" \
  >"$scratch/exclusive-out" 2>"$scratch/exclusive-err" &
fixture_pids+=("$!")
for attempt in {1..100}; do
  [[ -s "$scratch/exclusive-ready" ]] && break
  sleep 0.05
done
[[ -s "$scratch/exclusive-ready" ]]
probe=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class moderate || true)
[[ $(jq -r '.reason' <<<"$probe") == DEFER_EXCLUSIVE ]]
kill -TERM "${fixture_pids[0]}"
wait "${fixture_pids[0]}" || true
fixture_pids=()
[[ $(tail -n 1 "$scratch/exclusive-err" | jq -r '.decision') == RELEASED ]]
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" release \
  --lease "$lease" --owner fixture:/capacity

# A foreground session has no deadline, but keeps its allowance until its
# scope and descendants stop. Probing must not reclaim its null expiry.
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" session \
  --class moderate --owner fixture:/capacity \
  -- bash -c 'IFS=: read -r _ _ group < /proc/self/cgroup; printf "%s\n" "$group" >"$1"; sleep 60 & printf "%s\n" "$!" >"$2"; wait' \
  fixture-session "$scratch/session-group" "$scratch/session-child" \
  >"$scratch/session-out" 2>"$scratch/session-err" &
fixture_pids+=("$!")
for attempt in {1..100}; do
  [[ -s "$scratch/session-child" ]] && break
  sleep 0.05
done
read -r group <"$scratch/session-group"
read -r session_child <"$scratch/session-child"
[[ $(systemctl --user show "${group##*/}" --property=RuntimeMaxUSec --value) == infinity ]]
[[ $(head -n 1 "$scratch/session-err" | jq -r '.expiresAt') == null ]]
probe=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class exclusive || true)
[[ $(jq -r '.reason' <<<"$probe") == DEFER_EXCLUSIVE ]]
[[ $(jq -r '.leasedMemoryMiB' <<<"$probe") -eq 2048 ]]
[[ $(jq -r '.reclaimed' <<<"$probe") -eq 0 ]]
kill -TERM "${fixture_pids[0]}"
wait "${fixture_pids[0]}" || true
fixture_pids=()
[[ $(tail -n 1 "$scratch/session-err" | jq -r '.decision') == RELEASED ]]
[[ ! -e "/sys/fs/cgroup$group" ]]
! kill -0 "$session_child" 2>/dev/null
set +e
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" session \
  --class moderate --owner fixture:/capacity -- bash -c 'exit 7' 2>"$scratch/session-exit"
session_status=$?
set -e
[[ $session_status -eq 7 ]]
[[ $(tail -n 1 "$scratch/session-exit" | jq -r '.decision') == RELEASED ]]
[[ $(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent | jq -r '.leasedMemoryMiB') -eq 0 ]]

printf 'machine-capacity policy, aggregate enforcement, and session lifetime: PASS\n'
