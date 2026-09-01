#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/machine-capacity-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT

"$here/build-machine-capacity" "$scratch/machine-capacity.mjs"
cmp -- "$here/machine-capacity.mjs" "$scratch/machine-capacity.mjs"

fixture() {
  bun "$scratch/machine-capacity.mjs" fixture \
    --class "${1}" \
    --cores 24 \
    --memory-total-mib 96000 \
    --memory-available-mib "${2}" \
    --cpu-some-avg10-basis-points "${3}" \
    --memory-full-avg10-basis-points "${4}" \
    --leased-cpus "${5}" \
    --leased-memory-mib "${6}"
}

[[ $(fixture heavy 70000 500 0 6 8192) == '{"decision":"RUN","class":"heavy","cpus":6,"memoryMiB":8192}' ]]
[[ $(fixture exclusive 70000 500 0 0 0) == '{"decision":"RUN","class":"exclusive","cpus":18,"memoryMiB":16384}' ]]
[[ $(fixture heavy 70000 2000 0 0 0 || true) == '{"decision":"DEFER_CPU_PRESSURE","class":"heavy","cpus":6,"memoryMiB":8192}' ]]
[[ $(fixture heavy 21000 0 0 0 0 || true) == '{"decision":"DEFER_MEMORY_HEADROOM","class":"heavy","cpus":6,"memoryMiB":8192}' ]]
[[ $(fixture heavy 70000 0 0 15 8192 || true) == '{"decision":"DEFER_CPU_CAPACITY","class":"heavy","cpus":6,"memoryMiB":8192}' ]]
[[ $(fixture heavy 70000 0 1 0 0 || true) == '{"decision":"DEFER_MEMORY_PRESSURE","class":"heavy","cpus":6,"memoryMiB":8192}' ]]

fixture_runtime="$scratch/runtime"
reservation=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" reserve \
  --class exclusive --owner fixture:/capacity --timeout-seconds 5)
lease=$(jq -r '.lease' <<<"$reservation")
[[ $lease =~ ^[0-9a-f-]{36}$ ]]
blocked=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent || true)
[[ $(jq -r '.reason' <<<"$blocked") == DEFER_CPU_CAPACITY ]]
renewed=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" renew \
  --lease "$lease" --owner fixture:/capacity --timeout-seconds 5)
[[ $(jq -r '.decision' <<<"$renewed") == RENEWED ]]
released=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" release \
  --lease "$lease" --owner fixture:/capacity)
[[ $(jq -r '.decision' <<<"$released") == RELEASED ]]

expiring=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" reserve \
  --class agent --owner fixture:/capacity --timeout-seconds 1)
[[ $(jq -r '.decision' <<<"$expiring") == RESERVED ]]
sleep 1.1
reclaimed=$(XDG_RUNTIME_DIR="$fixture_runtime" bun "$scratch/machine-capacity.mjs" probe --class agent)
[[ $(jq -r '.reclaimed' <<<"$reclaimed") == 1 ]]

sleeper_pid_file="$scratch/sleeper.pid"
set +e
bun "$scratch/machine-capacity.mjs" run \
  --class agent \
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
