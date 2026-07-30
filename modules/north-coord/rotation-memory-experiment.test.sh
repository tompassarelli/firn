#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
harness=${HARNESS_UNDER_TEST:-"$here/rotation-memory-experiment"}
scratch=$(mktemp -d)
trap 'rm -rf "${scratch:?}"' EXIT

passes=0
check() {
  local label=$1
  shift
  if "$@"; then
    passes=$((passes + 1))
  else
    printf 'FAIL: %s\n' "$label" >&2
    exit 1
  fi
}

expect_failure() {
  local label=$1
  shift
  if "$@" >"$scratch/expected-failure.out" 2>&1; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$label" >&2
    exit 1
  fi
  passes=$((passes + 1))
}

if [[ ! -x "$harness" ]]; then
  printf 'missing executable rotation-memory experiment harness: %s\n' "$harness" >&2
  exit 1
fi

plan=$scratch/plan.tsv
"$harness" plan >"$plan"

check "contract version" grep -Fxq $'meta\tcontract\trotation-memory/v1' "$plan"
check "exact corpus count" grep -Fxq $'meta\tcorpus_facts\t350701' "$plan"
check "six base runs" grep -Fxq $'meta\tbase_process_starts\t6' "$plan"
check "hard maximum eight" grep -Fxq $'meta\thard_max_process_starts\t8' "$plan"
check "45 minute wall stop" grep -Fxq $'meta\twall_timeout_seconds\t2700' "$plan"
check "one fallback per role" grep -Fxq $'meta\tmax_fallbacks_per_role\t1' "$plan"
check "unchanged aggregate ceiling" \
  grep -Fxq $'meta\taggregate_ceiling_bytes\t9663676416' "$plan"
check "telemetry observed floor" \
  grep -Fxq $'meta\ttelemetry_floor_bytes\t1566572544' "$plan"
check "no selected margin" \
  grep -Fxq $'meta\toperational_margin_selected\tfalse' "$plan"
check "six enumerated base rows" \
  test "$(awk -F $'\t' '$1 == "run" && $3 == "base" {n++} END {print n+0}' "$plan")" -eq 6
check "two enumerated contingency rows" \
  test "$(awk -F $'\t' '$1 == "run" && $3 == "fallback" {n++} END {print n+0}' "$plan")" -eq 2
check "coord discovery profile" \
  grep -Fxq $'run\tcoord-discovery\tbase\tA\tcoordination\tcoordination\t-Xmx2g\tinfinity\t12-17\t-' "$plan"
check "telemetry discovery profile" \
  grep -Fxq $'run\ttelemetry-discovery\tbase\tA\ttelemetry\ttelemetry\t-Xmx1g\tinfinity\t18-23\t-' "$plan"
check "coord blue profile" \
  grep -Fxq $'run\tcoord-blue\tbase\tB\tcoordination\tcoordination\t-Xmx2g\t3G\t12-14\t-' "$plan"
check "coord green profile" \
  grep -Fxq $'run\tcoord-green\tbase\tB\tcoordination\tcoordination\t-Xmx2g\t3G\t15-17\t-' "$plan"
check "telemetry blue profile" \
  grep -Fxq $'run\ttelemetry-blue\tbase\tB\ttelemetry\ttelemetry\t-Xmx1g\t1500M\t18-20\t-' "$plan"
check "telemetry green profile" \
  grep -Fxq $'run\ttelemetry-green\tbase\tB\ttelemetry\ttelemetry\t-Xmx1g\t1500M\t21-23\t-' "$plan"
check "coord fallback profile" \
  grep -Fxq $'run\tcoord-fallback\tfallback\tF\tcoordination\tcoordination\t-Xmx4g\tinfinity\t12-17\tcoord-discovery' "$plan"
check "telemetry fallback profile" \
  grep -Fxq $'run\ttelemetry-fallback\tfallback\tF\ttelemetry\ttelemetry\t-Xmx2g\tinfinity\t18-23\ttelemetry-discovery' "$plan"
check "fallback and contamination retry are exclusive" \
  grep -Fxq $'policy\tcontingency\tfallback-or-one-wave-a-retry\tmutually-exclusive' "$plan"

mock_bin=$scratch/mock-bin
mkdir -p "$mock_bin"
cat >"$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
: >"${ROTATION_MEMORY_TEST_SYSTEMCTL_CALLED:?}"
exit 99
EOF
chmod +x "$mock_bin/systemctl"
systemctl_called=$scratch/systemctl.called
run_scratch=$scratch/run-scratch
mkdir -p "$run_scratch"
valid_rev=0000000000000000000000000000000000000000
expect_failure "real run requires explicit Fram repository" \
  env PATH="$mock_bin:$PATH" ROTATION_MEMORY_TEST_SYSTEMCTL_CALLED="$systemctl_called" \
    "$harness" run --fram-rev "$valid_rev" --scratch-parent "$run_scratch"
check "missing Fram repository diagnostic" \
  grep -Fxq 'rotation-memory-experiment: --fram-repo is required' \
    "$scratch/expected-failure.out"
expect_failure "real run rejects missing Fram repository directory" \
  env PATH="$mock_bin:$PATH" ROTATION_MEMORY_TEST_SYSTEMCTL_CALLED="$systemctl_called" \
    "$harness" run --fram-rev "$valid_rev" \
      --fram-repo "$scratch/missing-fram" --scratch-parent "$run_scratch"
check "missing Fram repository directory diagnostic" \
  grep -Fxq "rotation-memory-experiment: directory does not exist: $scratch/missing-fram" \
    "$scratch/expected-failure.out"
check "repository rejection precedes systemd preflight" test ! -e "$systemctl_called"
check "repository rejection creates no experiment scratch" \
  test -z "$(find "$run_scratch" -mindepth 1 -print -quit)"

fixture=$scratch/fixture
"$harness" generate-fixture "$fixture"
check "fixture line count" test "$(wc -l <"$fixture/coordination.log")" -eq 350701
check "fixture telemetry log empty" test ! -s "$fixture/telemetry.log"
check "fixture title count" \
  test "$(rg -c ':p "title"' "$fixture/coordination.log")" -eq 116900
check "fixture lead count" \
  test "$(rg -c ':p "lead"' "$fixture/coordination.log")" -eq 1623
check "fixture agent-kind count" \
  test "$(rg -c ':p "kind", :r "agent"' "$fixture/coordination.log")" -eq 32
check "fixture pad count" \
  test "$(rg -c ':p "benchmark_pad"' "$fixture/coordination.log")" -eq 1
check "fixture receipt says exact count" \
  grep -Fxq 'fact_count=350701' "$fixture/fixture.receipt"
check "fixture hashes captured" test -s "$fixture/fixture.sha256"

safe_root=$scratch/safe
mkdir -p "$safe_root/case"
check "scratch-only identity accepted" \
  "$harness" safety-check \
    "$safe_root" 0 fram-rotmem-deadbeef-coord-discovery.service \
    "$safe_root/case/coordination.log" "$safe_root/case/telemetry.log"
expect_failure "canonical coordination port rejected" \
  "$harness" safety-check \
    "$safe_root" 7977 fram-rotmem-deadbeef-coord-discovery.service \
    "$safe_root/case/coordination.log" "$safe_root/case/telemetry.log"
expect_failure "private deployed port rejected" \
  "$harness" safety-check \
    "$safe_root" 17977 fram-rotmem-deadbeef-coord-discovery.service \
    "$safe_root/case/coordination.log" "$safe_root/case/telemetry.log"
expect_failure "canonical state root rejected" \
  "$harness" safety-check \
    /home/tom/.local/state/north 0 fram-rotmem-deadbeef-coord-discovery.service \
    /home/tom/.local/state/north/coordination.log \
    /home/tom/.local/state/north/telemetry.log
expect_failure "live unit rejected" \
  "$harness" safety-check \
    "$safe_root" 0 north-coord-blue.service \
    "$safe_root/case/coordination.log" "$safe_root/case/telemetry.log"
expect_failure "selector unit rejected" \
  "$harness" safety-check \
    "$safe_root" 0 north-coord-proxy.service \
    "$safe_root/case/coordination.log" "$safe_root/case/telemetry.log"
expect_failure "log outside scratch rejected" \
  "$harness" safety-check \
    "$safe_root" 0 fram-rotmem-deadbeef-coord-discovery.service \
    /tmp/outside-coordination.log "$safe_root/case/telemetry.log"
expect_failure "same corpus paths rejected" \
  "$harness" safety-check \
    "$safe_root" 0 fram-rotmem-deadbeef-coord-discovery.service \
    "$safe_root/case/coordination.log" "$safe_root/case/coordination.log"

write_case() {
  local dir=$1 exit_code=$2 signal=$3 ready=$4 work=$5 result=$6
  local before_max=$7 before_oom=$8 before_kill=$9
  shift 9
  local after_max=$1 after_oom=$2 after_kill=$3 peak=$4 oome=$5
  mkdir -p "$dir"
  {
    printf 'exit_code=%s\n' "$exit_code"
    printf 'signal=%s\n' "$signal"
    printf 'ready=%s\n' "$ready"
    printf 'work_complete=%s\n' "$work"
    printf 'systemd_result=%s\n' "$result"
    printf 'memory_peak=%s\n' "$peak"
  } >"$dir/run.meta"
  {
    printf 'max %s\n' "$before_max"
    printf 'oom %s\n' "$before_oom"
    printf 'oom_kill %s\n' "$before_kill"
  } >"$dir/memory.events.before"
  {
    printf 'max %s\n' "$after_max"
    printf 'oom %s\n' "$after_oom"
    printf 'oom_kill %s\n' "$after_kill"
  } >"$dir/memory.events.after"
  if [[ "$oome" == 1 ]]; then
    printf 'java.lang.OutOfMemoryError: Java heap space\n' >"$dir/daemon.log"
  else
    printf 'fixture daemon terminal\n' >"$dir/daemon.log"
  fi
}

write_case "$scratch/pass" 0 0 1 1 success 0 0 0 0 0 0 2500000000 0
check "pass classification" test "$("$harness" classify "$scratch/pass")" = pass
write_case "$scratch/heap" 1 0 0 0 failed 0 0 0 0 0 0 2600000000 1
check "heap OOME classification" \
  test "$("$harness" classify "$scratch/heap")" = heap-oome
write_case "$scratch/max" 1 0 0 0 failed 0 0 0 2 0 0 2800000000 0
check "cgroup max-pressure classification" \
  test "$("$harness" classify "$scratch/max")" = cgroup-max
write_case "$scratch/oom" 137 9 0 0 oom-kill 0 0 0 2 1 1 3000000000 0
check "cgroup OOM classification" \
  test "$("$harness" classify "$scratch/oom")" = cgroup-oom
write_case "$scratch/unknown" 1 0 0 0 failed 0 0 0 0 0 0 1 0
check "ambiguous failure is cannot-determine" \
  test "$("$harness" classify "$scratch/unknown")" = cannot-determine
rm "$scratch/unknown/memory.events.after"
check "missing cgroup metric is cannot-determine" \
  test "$("$harness" classify "$scratch/unknown")" = cannot-determine

receipts=$scratch/receipts
mkdir -p "$receipts"
printf '%s\n' role=coordination classification=pass memory_peak=2500000000 \
  >"$receipts/coord-blue.receipt"
printf '%s\n' role=coordination classification=pass memory_peak=2600000000 \
  >"$receipts/coord-green.receipt"
printf '%s\n' role=telemetry classification=pass memory_peak=1400000000 \
  >"$receipts/telemetry-blue.receipt"
printf '%s\n' role=telemetry classification=pass memory_peak=1500000000 \
  >"$receipts/telemetry-green.receipt"
report=$scratch/report
"$harness" report "$receipts" >"$report"
check "coord lower bound math" grep -Fxq 'coord_lower_bound_bytes=2600000000' "$report"
check "telemetry floor math" \
  grep -Fxq 'telemetry_lower_bound_bytes=1566572544' "$report"
check "aggregate lower bound math" \
  grep -Fxq 'aggregate_lower_bound_bytes=8333145088' "$report"
check "residual headroom math" \
  grep -Fxq 'residual_headroom_bytes=1330531328' "$report"
check "report declines margin selection" \
  grep -Fxq 'operational_margin_selected=false' "$report"

mkdir -p "$scratch/mock-parent"
mock_one=$scratch/mock-one
mock_two=$scratch/mock-two
"$harness" mock-run "$scratch/mock-parent" "$mock_one"
"$harness" mock-run "$scratch/mock-parent" "$mock_two"
root_one=$(sed -n 's/^scratch_root=//p' "$mock_one/summary.receipt")
root_two=$(sed -n 's/^scratch_root=//p' "$mock_two/summary.receipt")
check "mock roots are unique" test "$root_one" != "$root_two"
check "mock run uses six base cases" \
  test "$(find "$mock_one/cases" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 6
check "mock run stays below hard maximum" \
  grep -Fxq 'process_starts=6' "$mock_one/summary.receipt"
check "mock run records hard cap" \
  grep -Fxq 'hard_max_process_starts=8' "$mock_one/summary.receipt"
# shellcheck disable=SC2016
check "mock ports are kernel-selected and high" \
  awk -F= '/^port=/{if ($2 < 32768 || $2 > 60999) exit 1; n++} END {exit n == 6 ? 0 : 1}' \
    "$mock_one"/cases/*/run.receipt
check "mock identities are unique" \
  test "$(sed -n 's/^unit=//p' "$mock_one"/cases/*/run.receipt | sort -u | wc -l)" -eq 6
check "mock captures required receipt fields" \
  awk -F= '
    /^argv=/{argv++}
    /^role=/{role++}
    /^heap=/{heap++}
    /^memory_max=/{cap++}
    /^exit_code=/{exit_code++}
    /^signal=/{signal++}
    /^heap_oome=/{oome++}
    /^memory_peak=/{peak++}
    /^memory_events_oom_delta=/{oom++}
    /^memory_events_oom_kill_delta=/{kill++}
    /^ready=/{ready++}
    /^work_complete=/{work++}
    END {
      exit argv == 6 && role == 6 && heap == 6 && cap == 6 &&
           exit_code == 6 && signal == 6 && oome == 6 && peak == 6 &&
           oom == 6 && kill == 6 && ready == 6 && work == 6 ? 0 : 1
    }' "$mock_one"/cases/*/run.receipt
check "mock never launches systemd" test ! -e "$mock_one/systemd-run.called"

printf 'rotation-memory experiment harness: %d assertions passed\n' "$passes"
