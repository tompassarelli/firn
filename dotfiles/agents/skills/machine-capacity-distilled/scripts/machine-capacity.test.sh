#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/machine-capacity-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
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
    --leased-memory-mib "${6}"
}

[[ $(fixture heavy 70000 500 0 6 8192) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":0}' ]]
[[ $(fixture exclusive 70000 500 0 0 0) == '{"decision":"RUN","class":"exclusive","cpus":18,"memoryMiB":16384,"memoryFullAvg10":0}' ]]
[[ $(fixture heavy 70000 2000 394 0 0 || true) == '{"decision":"DEFER_CPU_PRESSURE","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 21000 0 394 0 0 || true) == '{"decision":"DEFER_MEMORY_HEADROOM","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 70000 0 394 15 8192 || true) == '{"decision":"DEFER_CPU_CAPACITY","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 70000 0 394 0 70000 || true) == '{"decision":"DEFER_MEMORY_CAPACITY","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture agent 73412 0 394 8 9728) == '{"decision":"RUN","class":"agent","cpus":1,"memoryMiB":768,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 73412 0 394 8 9728) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":3.94}' ]]
[[ $(fixture heavy 73412 0 10000 8 9728) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192,"memoryFullAvg10":100}' ]]

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

printf 'machine-capacity policy fixture: PASS\n'
