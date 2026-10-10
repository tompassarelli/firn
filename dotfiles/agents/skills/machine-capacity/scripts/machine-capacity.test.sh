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
# Live runs read recorded system CPU pressure, so other machine load cannot hold them.
export AGENT_CAPACITY_CPU_PRESSURE="$scratch/cpu.pressure"
calm_pressure() { printf 'some avg10=%s avg60=0.00 avg300=0.00 total=0\n' "$1" >"$AGENT_CAPACITY_CPU_PRESSURE"; }
calm_pressure 0.00
export AGENT_CAPACITY_GPU_BUSY="$scratch/gpu-busy" AGENT_CAPACITY_GPU_CLIENTS=0 AGENT_CAPACITY_USAGE_LOG="$scratch/usage.jsonl"
echo 0 >"$AGENT_CAPACITY_GPU_BUSY"

"$here/build-machine-capacity" "$scratch/machine-capacity.mjs"
cmp -- "$here/machine-capacity.mjs" "$scratch/machine-capacity.mjs"

# Arguments: profile class available-MiB protected-slice-PSI memory-full-PSI
# leased-CPU-ceilings leased-MiB [options]. Protected PSI is the session and
# native slices' own CPU wait, not the system-wide figure batch work inflates.
fixture() {
  bun "$scratch/machine-capacity.mjs" fixture \
    --profile "${1}" \
    --class "${2}" \
    --cores 24 \
    --memory-total-mib 96343 \
    --memory-available-mib "${3}" \
    --protected-cpu-some-avg10-basis-points "${4}" \
    --memory-full-avg10-basis-points "${5}" \
    --leased-cpus "${6}" \
    --leased-memory-mib "${7}" "${@:8}" | jq -c 'del(.leasedCpuCeilings)'
}
decision() { fixture "$@" | jq -r '.decision' || true; }

[[ $(fixture attended heavy 70000 500 0 6 8192) == '{"decision":"RUN","profile":"attended","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":0,"aggregateCpuLimit":20}' ]]
[[ $(fixture unattended exclusive 70000 500 0 0 0) == '{"decision":"RUN","profile":"unattended","class":"exclusive","cpus":24,"memoryMiB":16384,"memoryFullAvg10":0,"aggregateCpuLimit":24}' ]]
# Present: batch yields when the desktop itself waits for CPU. Away: no CPU refusal.
[[ $(decision attended heavy 70000 1000 394 0 0) == DEFER_INTERACTIVE_PRESSURE ]]
[[ $(decision attended heavy 70000 999 394 0 0) == RUN ]]
[[ $(decision unattended heavy 70000 10000 394 0 0) == RUN ]]
# Batch ceilings past the aggregate limit queue new batch work in every profile.
[[ $(decision attended moderate 70109 0 0 26 32768 --peer-batch-runs 7) == DEFER_CPU_CAPACITY ]]
[[ $(decision attended moderate 70109 0 0 18 32768 --peer-batch-runs 7) == RUN ]]
# Memory floor: 20% of RAM present, the hard 8 GiB floor away.
[[ $(decision attended heavy 21000 0 394 0 0) == DEFER_MEMORY_HEADROOM ]]
[[ $(decision unattended heavy 21000 0 394 0 0) == RUN ]]
[[ $(decision unattended heavy 16000 0 394 0 0) == DEFER_MEMORY_HEADROOM ]]
[[ $(decision unattended moderate 10241 0 0 0 0) == RUN ]]
[[ $(decision unattended heavy 70000 0 394 0 70000) == DEFER_MEMORY_CAPACITY ]]
[[ $(decision attended agent 73412 5000 394 8 9728) == RUN ]]
[[ $(decision attended heavy 73412 0 10000 8 9728) == RUN ]]
# Native clients ignore pressure and exclusive batch work; they are bounded by
# cores outside the present reserve and by memory.
[[ $(fixture attended native 70000 5000 0 0 0) == '{"decision":"RUN","profile":"attended","class":"native","cpus":2,"memoryMiB":4096,"memoryFullAvg10":0,"aggregateCpuLimit":20}' ]]
[[ $(decision attended native 70000 0 0 18 0 --leased-native-cpus 18) == RUN ]]
[[ $(decision attended native 70000 0 0 20 0 --leased-native-cpus 20) == DEFER_NATIVE_CPUS ]]
[[ $(decision unattended native 70000 0 0 20 0 --leased-native-cpus 20) == RUN ]]
[[ $(decision attended native 70000 0 0 24 16384 --peer-exclusive-runs 1) == RUN ]]
[[ $(decision attended native 12000 0 0 0 0) == DEFER_MEMORY_HEADROOM ]]
# A smaller client request retains the existing floor and leased-memory cap.
[[ $(decision unattended native 40000 0 0 0 70000) == DEFER_MEMORY_CAPACITY ]]
[[ $(fixture unattended native 40000 0 0 0 70000 --memory-gib 1.5 | jq -r '.memoryMiB') -eq 1536 ]]
[[ $(decision unattended native 40000 0 0 0 70000 --memory-gib 1.5) == RUN ]]
[[ $(decision unattended native 9600 0 0 0 0 --memory-gib 1.5) == DEFER_MEMORY_HEADROOM ]]
[[ $(decision attended native 20000 0 0 0 0 --memory-gib 1.5) == DEFER_MEMORY_HEADROOM ]]
[[ $(decision unattended native 40000 0 0 0 71000 --memory-gib 1.5) == DEFER_MEMORY_CAPACITY ]]
for memory in 0 -1 NaN Infinity 1.0001 100000000000000; do
  if fixture unattended native 40000 0 0 0 0 --memory-gib "$memory" >/dev/null 2>&1; then
    printf 'invalid memory request accepted: %s\n' "$memory" >&2
    exit 1
  fi
done
if fixture unattended heavy 40000 0 0 0 0 --memory-gib 1.5 >/dev/null 2>&1; then
  printf 'batch memory override accepted\n' >&2
  exit 1
fi

# Headless renders share the GPU two at a time and yield to native clients;
# GPU time leased renders hold does not defer a native client.
[[ $(decision unattended gpu 80000 0 0 1 2048 --gpu-runs 1) == RUN ]]
[[ $(decision unattended gpu 80000 0 0 2 4096 --gpu-runs 2) == DEFER_GPU_SLOTS ]]
[[ $(decision unattended gpu 80000 0 0 0 0 --native-waiting 1) == DEFER_NATIVE_WAITING ]]
[[ $(decision unattended native 80000 0 0 0 0 --gpu-busy-percent 95) == DEFER_GPU_BUSY ]]
[[ $(decision unattended native 80000 0 0 2 4096 --gpu-busy-percent 95 --gpu-runs 2) == RUN ]]
[[ $(decision attended native 80000 0 0 0 0 --gpu-clients 3 --gpu-runs 1) == RUN ]]
[[ $(decision attended native 80000 0 0 0 0 --gpu-clients 4 --gpu-runs 1) == DEFER_GPU_CLIENTS ]]

# Peer ceilings hold batch work at the aggregate limit: 20 cores present, 24 away.
[[ $(decision attended heavy 80000 0 0 18 21504 --peer-batch-runs 3) == DEFER_CPU_CAPACITY ]]
[[ $(decision attended heavy 80000 0 0 14 21504 --peer-batch-runs 3) == RUN ]]
[[ $(decision unattended heavy 80000 0 0 18 21504 --peer-batch-runs 3) == RUN ]]
[[ $(decision unattended heavy 80000 0 0 20 21504 --peer-batch-runs 4) == DEFER_CPU_CAPACITY ]]
# System CPU pressure above 30% holds moderate and heavy work, present or away.
[[ $(decision unattended heavy 80000 0 0 0 0 --cpu-some-avg10-basis-points 3001) == DEFER_CPU_PRESSURE ]]
[[ $(decision unattended heavy 80000 0 0 0 0 --cpu-some-avg10-basis-points 3000) == RUN ]]
[[ $(decision attended moderate 80000 0 0 0 0 --cpu-some-avg10-basis-points 8400) == DEFER_CPU_PRESSURE ]]
[[ $(decision unattended exclusive 80000 0 0 0 0 --cpu-some-avg10-basis-points 8400) == RUN ]]
[[ $(decision unattended native 80000 0 0 0 0 --cpu-some-avg10-basis-points 8400) == RUN ]]
[[ $(decision unattended heavy 80000 0 0 0 0 --queued-ahead 1) == DEFER_QUEUED ]]
[[ $(decision unattended native 80000 0 0 0 0 --queued-ahead 1) == RUN ]]
[[ $(decision attended exclusive 80000 0 0 4 3072) == RUN ]]
[[ $(decision attended exclusive 80000 0 0 2 2048 --peer-batch-runs 1) == DEFER_EXCLUSIVE ]]
[[ $(decision unattended moderate 80000 0 0 18 16384 --peer-batch-runs 1 --peer-exclusive-runs 1) == DEFER_EXCLUSIVE ]]
[[ $(decision attended heavy 80000 0 0 6 8192 --peer-batch-runs 1 --unbounded-runs 1) == DEFER_UNBOUNDED_PEER ]]
# A waiting exclusive request holds later heavy work and waits only for
# running batch leases: not for earlier batch tickets or pressure. Moderate
# builds and dependency updates still start.
[[ $(decision unattended heavy 80000 0 0 0 0 --exclusive-waiting 1) == DEFER_EXCLUSIVE_QUEUED ]]
[[ $(decision attended moderate 80000 0 0 0 0 --exclusive-waiting 1) == RUN ]]
[[ $(decision unattended native 80000 0 0 0 0 --exclusive-waiting 1) == RUN ]]
[[ $(decision unattended exclusive 80000 0 0 0 0 --queued-ahead 3) == RUN ]]
[[ $(decision unattended exclusive 80000 0 0 0 0 --exclusive-waiting 1) == DEFER_QUEUED ]]
[[ $(decision attended exclusive 80000 5000 0 0 0 --cpu-some-avg10-basis-points 9000) == RUN ]]
[[ $(decision attended exclusive 80000 5000 0 6 8192 --peer-batch-runs 1) == DEFER_EXCLUSIVE ]]
# Critical work skips the queue, a waiting exclusive and the CPU waits, keeps
# the attended desktop reserve, and still respects memory floors, a running
# exclusive lease and the desktop's own CPU wait.
[[ $(fixture unattended critical 70000 0 0 0 0 | jq -c '[.decision, .cpus]') == '["RUN",20]' ]]
[[ $(decision attended critical 80000 0 0 20 16384 --peer-batch-runs 4 --queued-ahead 3 --exclusive-waiting 1 --cpu-some-avg10-basis-points 9000) == RUN ]]
[[ $(decision unattended critical 20000 0 0 0 0) == DEFER_MEMORY_HEADROOM ]]
[[ $(decision unattended critical 80000 0 0 24 16384 --peer-batch-runs 1 --peer-exclusive-runs 1) == DEFER_EXCLUSIVE ]]
[[ $(decision attended critical 80000 1000 0 0 0) == DEFER_INTERACTIVE_PRESSURE ]]
[[ $(decision unattended heavy 80000 0 0 20 16384 --peer-batch-runs 1) == DEFER_CPU_CAPACITY ]]
[[ $(decision unattended exclusive 80000 0 0 20 16384 --peer-batch-runs 1) == DEFER_EXCLUSIVE ]]

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

# Four heavy jobs request 24 CPU ceilings on this 24-core host. The attended
# fixture admits three (18 of 20 cores) and queues the fourth; the kernel
# ancestor enforces the shared cap, which keeps four cores for the desktop.
for number in 1 2 3 4; do
  XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
    --class heavy --owner fixture:/capacity --timeout-seconds 30 \
    -- bash -c 'IFS=: read -r _ _ group < /proc/self/cgroup; printf "%s\n" "$group" >"$1"; sleep 60 & wait' \
    fixture-scope "$scratch/group-$number" >"$scratch/out-$number" 2>"$scratch/err-$number" &
  fixture_pids+=("$!")
  for attempt in {1..100}; do
    [[ $number -eq 4 || -s "$scratch/group-$number" ]] && break
    sleep 0.05
  done
done
sleep 2.5
for number in 1 2 3; do
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
  [[ $quota -eq $((period * (cores - 4))) ]]
  read -r quota period <"/sys/fs/cgroup$group/cpu.max"
  [[ $((quota / period)) -eq 6 ]]
  [[ $(cat "/sys/fs/cgroup$group/memory.high") -eq $((8192 * 1024 * 1024)) ]]
done
[[ ! -s "$scratch/group-4" ]]
[[ $(head -n 1 "$scratch/err-4" | jq -r '.decision + " " + .reason') == 'QUEUED DEFER_CPU_CAPACITY' ]]
probe=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class exclusive || true)
[[ $(jq -r '.reason' <<<"$probe") == DEFER_EXCLUSIVE ]]
[[ $(jq -r '.leasedCpuCeilings' <<<"$probe") -eq 18 ]]
[[ $(jq -r '.queuedAhead' <<<"$probe") -eq 1 ]]
[[ $(jq -r '.aggregateCpuLimit' <<<"$probe") -eq 20 ]]
[[ $(jq -r '.profile' <<<"$probe") == attended ]]
# Releasing one job starts the queued one.
kill -TERM "${fixture_pids[0]}"
for attempt in {1..100}; do
  [[ -s "$scratch/group-4" ]] && break
  sleep 0.05
done
[[ -s "$scratch/group-4" ]]
for pid in "${fixture_pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
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

# Pressure holds a run in the queue until it eases; leaving the queue drops the ticket.
calm_pressure 90.00
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
  --class moderate --owner fixture:/capacity --timeout-seconds 30 \
  -- bash -c 'printf ready >"$1"; sleep 60 & wait' fixture-held "$scratch/held-ready" \
  >"$scratch/held-out" 2>"$scratch/held-err" &
fixture_pids+=("$!")
sleep 2.5
[[ ! -s "$scratch/held-ready" ]]
[[ $(head -n 1 "$scratch/held-err" | jq -r '.decision') == QUEUED ]]
[[ $(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent | jq -r '.queuedAhead') -eq 1 ]]
calm_pressure 0.00
for attempt in {1..100}; do
  [[ -s "$scratch/held-ready" ]] && break
  sleep 0.05
done
[[ -s "$scratch/held-ready" ]]
kill -TERM "${fixture_pids[0]}"
wait "${fixture_pids[0]}" || true
fixture_pids=()
[[ $(tail -n 1 "$scratch/held-err" | jq -r '.decision') == RELEASED ]]
calm_pressure 90.00
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
  --class heavy --owner fixture:/capacity --timeout-seconds 30 -- true 2>/dev/null &
fixture_pids+=("$!")
sleep 1
[[ $(ls "$fixture_runtime/agent-capacity-v1/queue" | wc -l) -eq 1 ]]
kill -TERM "${fixture_pids[0]}"
wait "${fixture_pids[0]}" || true
fixture_pids=()
[[ $(ls "$fixture_runtime/agent-capacity-v1/queue" | wc -l) -eq 0 ]]
calm_pressure 0.00

# A batch session takes its class's default deadline and keeps its allowance
# until its scope and descendants stop.
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
[[ $(systemctl --user show "${group##*/}" --property=RuntimeMaxUSec --value) == 30min ]]
[[ $(head -n 1 "$scratch/session-err" | jq -r '.expiresAt') != null ]]
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

# A native client runs unthrottled at high weight beside the batch slice.
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
  --class native --owner fixture:/capacity --timeout-seconds 30 \
  -- bash -c 'IFS=: read -r _ _ group < /proc/self/cgroup; printf "%s\n" "$group" >"$1"; sleep 60 & wait' \
  fixture-native "$scratch/native-group" >"$scratch/native-out" 2>"$scratch/native-err" &
fixture_pids+=("$!")
for attempt in {1..100}; do
  [[ -s "$scratch/native-group" ]] && break
  sleep 0.05
done
read -r group <"$scratch/native-group"
[[ ${group%/*} == */native.slice ]]
[[ $(cat "/sys/fs/cgroup${group%/*}/cpu.weight") -eq 200 ]]
[[ ! -e "/sys/fs/cgroup$group/cpu.max" || $(cut -d' ' -f1 "/sys/fs/cgroup$group/cpu.max") == max ]]
[[ $(cat "/sys/fs/cgroup$group/memory.high") -eq $((4096 * 1024 * 1024)) ]]
probe=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class heavy)
[[ $(jq -r '.decision' <<<"$probe") == RUN ]]
[[ $(jq -r '.leasedNativeCpus' <<<"$probe") -eq 2 ]]
kill -TERM "${fixture_pids[0]}"
wait "${fixture_pids[0]}" || true
fixture_pids=()
[[ $(tail -n 1 "$scratch/native-err" | jq -r '.decision') == RELEASED ]]

# Requests reach both lease accounting and the kernel for runs and sessions.
for lifetime in run session; do
  options=()
  [[ $lifetime != run ]] || options=(--timeout-seconds 30)
  XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" "$lifetime" \
    --class native --memory-gib 1.5 --owner fixture:/capacity "${options[@]}" \
    -- bash -c 'IFS=: read -r _ _ group < /proc/self/cgroup; printf "%s\n" "$group" >"$1"; sleep 60 & wait' \
    fixture-native-memory "$scratch/memory-group-$lifetime" \
    >"$scratch/memory-out-$lifetime" 2>"$scratch/memory-err-$lifetime" &
  fixture_pids+=("$!")
  for attempt in {1..100}; do
    [[ -s "$scratch/memory-group-$lifetime" ]] && break
    sleep 0.05
  done
  read -r group <"$scratch/memory-group-$lifetime"
  [[ $(cat "/sys/fs/cgroup$group/memory.high") -eq 1610612736 ]]
  # Native sessions alone have no deadline; probing must not reclaim it.
  [[ $lifetime == run || $(systemctl --user show "${group##*/}" --property=RuntimeMaxUSec --value) == infinity ]]
  [[ $(head -n 1 "$scratch/memory-err-$lifetime" | jq -r '.requestedMemoryMiB') -eq 1536 ]]
  lease=$(head -n 1 "$scratch/memory-err-$lifetime" | jq -r '.lease')
  [[ $(jq -r '.memoryMiB' "$fixture_runtime/agent-capacity-v1/leases/$lease.json") -eq 1536 ]]
  probe=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class native --memory-gib 1.5)
  [[ $(jq -r '.leasedMemoryMiB' <<<"$probe") -eq 1536 ]]
  [[ $(jq -r '.requestedMemoryMiB' <<<"$probe") -eq 1536 ]]
  kill -TERM "${fixture_pids[0]}"
  wait "${fixture_pids[0]}" || true
  fixture_pids=()
  [[ $(tail -n 1 "$scratch/memory-err-$lifetime" | jq -r '.decision') == RELEASED ]]
done

# Deadlines are capped per class: an hour for batch work, 15 minutes exclusive.
for request in 'exclusive 901' 'heavy 3601'; do
  read -r class seconds <<<"$request"
  set +e
  refused=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run \
    --class "$class" --owner fixture:/capacity --timeout-seconds "$seconds" -- true 2>&1)
  refused_status=$?
  set -e
  [[ $refused_status -eq 2 && $refused == *'--timeout-seconds must be an integer from 1 to'* ]]
done

wait_for() { for attempt in {1..100}; do [[ -s "$1" ]] && return 0; sleep 0.05; done; [[ -s "$1" ]]; }
held_run() {
  local class=$1 owner=$2 name=$3; shift 3
  XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" "$@" \
    --class "$class" --owner "fixture:/$owner" \
    -- bash -c 'IFS=: read -r _ _ group < /proc/self/cgroup; printf "%s\n" "$group" >"$1"; sleep 60 & wait' \
    fixture-drain "$scratch/$name-ready" >"$scratch/$name-out" 2>"$scratch/$name-err" &
  fixture_pids+=("$!")
  pid_of[$name]=$!
}
declare -A pid_of
stop_run() { kill -TERM "${pid_of[$1]}"; wait "${pid_of[$1]}" || true; }
status() { XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" status; }
# An exclusive request passes an earlier batch ticket held by pressure (the
# recorded file is also the protected slices' reading).
calm_pressure 90.00
held_run moderate early early run --timeout-seconds 30
sleep 1.5
[[ $(head -n 1 "$scratch/early-err" | jq -r '.reason') == DEFER_INTERACTIVE_PRESSURE ]]
held_run exclusive drain drain session
wait_for "$scratch/drain-ready"
read -r group <"$scratch/drain-ready"
[[ $(systemctl --user show "${group##*/}" --property=RuntimeMaxUSec --value) == 15min ]]
calm_pressure 0.00
sleep 2.5
[[ ! -s "$scratch/early-ready" ]]
[[ $(status | jq -c '[.holding[].owner, .queued[].owner, .queued[0].position]') == '["fixture:/drain","fixture:/early",1]' ]]
stop_run drain
wait_for "$scratch/early-ready"
# While a running lease holds the machine, a queued exclusive request goes first
# and later heavy work waits behind it; a moderate build still starts.
held_run exclusive drain second run --timeout-seconds 30
sleep 1.5
held_run moderate build build run --timeout-seconds 30
wait_for "$scratch/build-ready"
held_run heavy late late run --timeout-seconds 30
sleep 1.5
[[ $(head -n 1 "$scratch/second-err" | jq -r '.reason') == DEFER_EXCLUSIVE ]]
[[ $(head -n 1 "$scratch/late-err" | jq -r '.reason') == DEFER_EXCLUSIVE_QUEUED ]]
[[ $(status | jq -c '[.holding[] | .owner + " " + .class] + [.queued[] | .class]') == '["fixture:/early moderate","fixture:/build moderate","exclusive","heavy"]' ]]
[[ $(status | jq '.holding[0].remainingSeconds') -le 35 ]]
stop_run early
stop_run build
wait_for "$scratch/second-ready"
sleep 1.5
[[ ! -s "$scratch/late-ready" ]]
stop_run second
wait_for "$scratch/late-ready"
stop_run late
fixture_pids=()
[[ $(status | jq -c '[.holding, .queued]') == '[[],[]]' ]]

# Mode overrides select the profile; auto follows recorded input idleness.
mode=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" mode away)
[[ $(jq -r '.profile' <<<"$mode") == unattended ]]
[[ $(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent | jq -r '.profile') == unattended ]]
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" mode auto >/dev/null
touch -d '-11 minutes' "$fixture_runtime/agent-capacity-v1/last-input"
[[ $(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent | jq -r '.profile') == unattended ]]
touch "$fixture_runtime/agent-capacity-v1/last-input"
[[ $(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent | jq -r '.profile') == attended ]]
[[ $(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" mode present | jq -r '.profile') == attended ]]

# A lease scope throttled by its own CPUQuota stalls in /proc/pressure/cpu and
# agent.slice; that wait must not hold the queue. Other slices' wait still does.
cgroups="$scratch/cgroup"
user_manager="$cgroups/user.slice/user-$(id -u).slice/user@$(id -u).service"
lease_scope="$user_manager/agent.slice/agent-capacity-lease.scope"
mkdir -p "$cgroups/system.slice" "$lease_scope" "$user_manager"/{app,background,session,native}.slice
psi() { printf 'some avg10=%s avg60=0.00 avg300=0.00 total=0\n' "$2" >"$1/cpu.pressure"; }
for slice in "$cgroups/system.slice" "$user_manager"/{app,background,session,native}.slice; do psi "$slice" 0.00; done
psi "$user_manager/agent.slice" 90.00
psi "$lease_scope" 90.00
throttled_probe() {
  env -u AGENT_CAPACITY_CPU_PRESSURE AGENT_CAPACITY_CGROUP_ROOT="$cgroups" XDG_RUNTIME_DIR="$fixture_runtime" \
    bun "$scratch/machine-capacity.mjs" probe --class moderate | jq -r '.reason // .decision' || true
}
[[ $(throttled_probe) != DEFER_CPU_PRESSURE ]]
psi "$user_manager/app.slice" 90.00
[[ $(throttled_probe) == DEFER_CPU_PRESSURE ]]

# A deferred native client holds new gpu leases until it is admitted.
gpu_probe() { XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class "$1" | jq -r '.reason' || true; }
echo 95 >"$AGENT_CAPACITY_GPU_BUSY"
[[ $(gpu_probe native) == DEFER_GPU_BUSY ]]
[[ $(gpu_probe gpu) == DEFER_NATIVE_WAITING ]]
echo 0 >"$AGENT_CAPACITY_GPU_BUSY"
[[ $(gpu_probe native) == RUN ]]
[[ $(gpu_probe gpu) == RUN ]]

# Release records what the scope used: two busy loops under a 2-CPU quota.
XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run --class moderate --owner fixture:/measure \
  --timeout-seconds 30 -- bash -c 'cd / && timeout 3 sh -c "while :; do :; done" & timeout 3 sh -c "while :; do :; done"; wait' 2>/dev/null
measured=$(jq -c 'select(.owner == "fixture:/measure")' "$AGENT_CAPACITY_USAGE_LOG")
[[ $(jq -r '.shape' <<<"$measured") == sh ]]
[[ $(jq '.meanCores > 1.5 and .meanCores <= 2.1 and .peakCores <= 2.2 and .cpuSeconds > 4' <<<"$measured") == true ]]

# Without --class, run sizes the lease from the shape's p90 plus a quarter
# headroom; GPU-bound renders take the gpu class; unknown shapes start moderate.
for cores in 2.4 3.1 1.0; do
  printf '{"shape":"fixturebuild","wallSeconds":10,"peakCores":%s,"peakMemoryMiB":3000,"gpuSeconds":0}\n' "$cores"
  printf '{"shape":"fixturerender","wallSeconds":10,"peakCores":0.6,"peakMemoryMiB":700,"gpuSeconds":6}\n'
done >>"$AGENT_CAPACITY_USAGE_LOG"
for program in fixturebuild fixturerender fixturenew; do printf '#!/bin/sh\n' >"$scratch/$program"; chmod +x "$scratch/$program"; done
sized() {
  XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" run --owner fixture:/sized --timeout-seconds 30 \
    -- "$scratch/$1" 2>&1 >/dev/null | head -1 | jq -c '{class, requestedCpus, requestedMemoryMiB}'
}
[[ $(sized fixturebuild) == '{"class":"heavy","requestedCpus":4,"requestedMemoryMiB":3840}' ]]
[[ $(sized fixturerender) == '{"class":"gpu","requestedCpus":1,"requestedMemoryMiB":1024}' ]]
[[ $(sized fixturenew) == '{"class":"moderate","requestedCpus":2,"requestedMemoryMiB":2048}' ]]

# Unleased load: a cgroup outside lease scopes averaging over one core across two
# minutes is reported; the desktop session and lease scopes are not.
usage() { mkdir -p "$1"; printf 'usage_usec %s\nuser_usec 0\nsystem_usec 0\n' "$2" >"$1/cpu.stat"; }
unleased_sample() {
  env -u AGENT_CAPACITY_CPU_PRESSURE AGENT_CAPACITY_CGROUP_ROOT="$cgroups" AGENT_CAPACITY_NOW="$1" \
    XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" "${@:2}"
}
heavy_scopes=("$user_manager/app.slice/app-build.scope" "$user_manager/session.slice/niri.scope"
  "$user_manager/agent.slice/agent-capacity.slice/agent-capacity-0123abcd.scope")
for scope in "${heavy_scopes[@]}"; do usage "$scope" 0; done
[[ $(unleased_sample 1000000 sample-unleased) == null ]]
for scope in "${heavy_scopes[@]}"; do usage "$scope" 240000000; done
[[ $(unleased_sample 1120000 sample-unleased | jq -c '[.heavy[] | {cgroup, cores}]') == '[{"cgroup":"app.slice/app-build.scope","cores":2}]' ]]
[[ $(unleased_sample 1120000 status | jq -c '.unleasedHeavy | {cores, windowSeconds}') == '{"cores":2,"windowSeconds":120}' ]]
# The spawn gate's committed CPUs add unleased heavy load to live batch leases.
[[ $(unleased_sample 1120000 probe --class agent | jq -c '{leasedBatchCpus, committedBatchCpus}') == '{"leasedBatchCpus":0,"committedBatchCpus":2}' ]]

printf 'machine-capacity policy, aggregate enforcement, and session lifetime: PASS\n'
