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
check "one Wave-A retry" grep -Fxq $'meta\tmax_wave_a_retries\t1' "$plan"
check "host OOM contamination threshold is zero" \
  grep -Fxq $'meta\thost_oom_kill_delta_max\t0' "$plan"
check "unexpected cgroup PID threshold is zero" \
  grep -Fxq $'meta\tunexpected_cgroup_pid_max\t0' "$plan"
check "exact cgroup membership is runner plus daemon" \
  grep -Fxq $'meta\texpected_cgroup_member_count\t2' "$plan"
check "two enumerated retry rows" \
  test "$(awk -F $'\t' '$1 == "run" && $3 == "retry" {n++} END {print n+0}' "$plan")" -eq 2
check "coord retry reuses Wave-A profile" \
  grep -Fxq $'run\tcoord-discovery-retry\tretry\tR\tcoordination\tcoordination\t-Xmx2g\tinfinity\t12-17\tcoord-discovery' "$plan"
check "telemetry retry reuses Wave-A profile" \
  grep -Fxq $'run\ttelemetry-discovery-retry\tretry\tR\ttelemetry\ttelemetry\t-Xmx1g\tinfinity\t18-23\ttelemetry-discovery' "$plan"
check "host OOM producer is recorded" \
  grep -Fxq $'producer\thost_oom_kill\t/proc/vmstat:oom_kill\tcumulative-system-oom-kills' "$plan"
check "cgroup membership producer is recorded" \
  grep -Fxq $'producer\tunexpected_cgroup_pid_count\tcgroup.procs\texact-runner-daemon-membership' "$plan"

run_control_case() {
  local label=$1 expected_rc=$2 expected_starts=$3 expected_forced=$4
  local expected_exclusions=$5 expected_order=$6 outcomes=$7 contaminations=$8
  local output=$scratch/control-output trace=$scratch/control-trace rc
  : >"$trace"
  set +e
  # shellcheck disable=SC2016
  env HARNESS_UNDER_TEST="$harness" ROTATION_MEMORY_CONTROL_TRACE="$trace" \
    ROTATION_MEMORY_CONTROL_OUTCOMES="$outcomes" \
    ROTATION_MEMORY_CONTROL_CONTAMINATIONS="$contaminations" \
    bash -c '
      set -euo pipefail
      source "$HARNESS_UNDER_TEST"

      launch_case() {
        printf "%s\n" "$5" >>"$ROTATION_MEMORY_CONTROL_TRACE"
      }
      observe_case() {
        local root=$1 wanted=$3 pair key value role=coordination
        local -a pairs=()
        IFS=, read -r -a pairs <<<"$ROTATION_MEMORY_CONTROL_OUTCOMES"
        for pair in "${pairs[@]}"; do
          key=${pair%%=*}
          value=${pair#*=}
          if [[ "$key" == "$wanted" ]]; then
            [[ "$wanted" == telemetry-* ]] && role=telemetry
            printf "%s\n" "role=$role" "classification=$value" \
              "memory_peak=1000000000" "cgroup_members_exact=1" \
              "cgroup_member_count=2" "unexpected_cgroup_pid_count=0" \
              "decision_sample=eligible" \
              >"$root/receipts/$wanted.receipt"
            printf "%s\n" "$value"
            return 0
          fi
        done
        printf "cannot-determine\n"
      }
      capture_host_state() {
        : >"$1"
      }
      host_oom_kills() {
        printf "7\n"
      }
      # the harness calls wave_contamination in a command substitution, so the
      # scripted verdicts must be popped from a file, not from a shell variable
      wave_contamination() {
        local next
        next=$(head -n 1 "$contamination_queue")
        tail -n +2 "$contamination_queue" >"$contamination_queue.rest"
        mv "$contamination_queue.rest" "$contamination_queue"
        printf "%s\n" "${next:-cannot-determine}"
      }
      root=$(mktemp -d)
      trap "rm -rf \"${root:?}\"" EXIT
      mkdir -p "$root/results" "$root/receipts"
      contamination_queue=$root/contamination-queue
      printf "%s" "$ROTATION_MEMORY_CONTROL_CONTAMINATIONS" |
        tr , "\n" >"$contamination_queue"
      run_matrix_control "$root" /source /fixture deadbeef 9999999999
      excluded=0
      for receipt in "$root"/receipts/*.receipt; do
        if grep -q "^decision_sample=excluded-" "$receipt"; then
          excluded=$((excluded + 1))
        fi
      done
      printf "order=%s\n" "$(paste -sd, "$ROTATION_MEMORY_CONTROL_TRACE")"
      printf "starts=%s\n" "$starts"
      printf "forced=%s\n" "${MATRIX_FORCED_OVERALL:-none}"
      printf "excluded_counter=%s\n" "$MATRIX_DECISION_EXCLUSIONS"
      printf "excluded_receipts=%s\n" "$excluded"
      [[ "$MATRIX_FORCED_OVERALL" == cannot-determine ]] && exit 20
      exit 0
    ' >"$output" 2>&1
  rc=$?
  set -e
  if [[ "$rc" == "$expected_rc" ]] &&
     grep -Fxq "order=$expected_order" "$output" &&
     grep -Fxq "starts=$expected_starts" "$output" &&
     grep -Fxq "forced=$expected_forced" "$output" &&
     grep -Fxq "excluded_counter=$expected_exclusions" "$output" &&
     grep -Fxq "excluded_receipts=$expected_exclusions" "$output"; then
    passes=$((passes + 1))
  else
    printf 'FAIL: %s\n' "$label" >&2
    printf 'expected rc=%s starts=%s forced=%s exclusions=%s order=%s\n' \
      "$expected_rc" "$expected_starts" "$expected_forced" \
      "$expected_exclusions" "$expected_order" >&2
    sed 's/^/  /' "$output" >&2
    exit 1
  fi
}

run_control_case "one contaminated Wave A retries both arms then launches Wave B" 0 8 none 2 \
  "coord-discovery,telemetry-discovery,coord-discovery-retry,telemetry-discovery-retry,coord-blue,coord-green,telemetry-blue,telemetry-green" \
  "coord-discovery=pass,telemetry-discovery=pass,coord-discovery-retry=pass,telemetry-discovery-retry=pass,coord-blue=pass,coord-green=pass,telemetry-blue=pass,telemetry-green=pass" \
  contaminated,clean
run_control_case "clean Wave A launches six in order" 0 6 none 0 \
  "coord-discovery,telemetry-discovery,coord-blue,coord-green,telemetry-blue,telemetry-green" \
  "coord-discovery=pass,telemetry-discovery=pass,coord-blue=pass,coord-green=pass,telemetry-blue=pass,telemetry-green=pass" \
  clean
run_control_case "one heap OOME launches only its fallback" 0 3 none 0 \
  "coord-discovery,telemetry-discovery,coord-fallback" \
  "coord-discovery=heap-oome,telemetry-discovery=pass,coord-fallback=pass" \
  contaminated
run_control_case "two heap OOMEs launch both fallbacks and stop at four" 0 4 none 0 \
  "coord-discovery,telemetry-discovery,coord-fallback,telemetry-fallback" \
  "coord-discovery=heap-oome,telemetry-discovery=heap-oome,coord-fallback=pass,telemetry-fallback=pass" \
  contaminated
run_control_case "second contaminated Wave A is CANNOT at four starts" 20 4 cannot-determine 4 \
  "coord-discovery,telemetry-discovery,coord-discovery-retry,telemetry-discovery-retry" \
  "coord-discovery=pass,telemetry-discovery=pass,coord-discovery-retry=pass,telemetry-discovery-retry=pass" \
  contaminated,contaminated
run_control_case "undetermined Wave A contamination excludes without retrying" 20 2 cannot-determine 2 \
  "coord-discovery,telemetry-discovery" \
  "coord-discovery=pass,telemetry-discovery=pass" \
  cannot-determine
run_control_case "a failed Wave A arm stops before any contingency" 0 2 none 0 \
  "coord-discovery,telemetry-discovery" \
  "coord-discovery=pass,telemetry-discovery=cgroup-max" \
  contaminated

# shellcheck source=/dev/null
source "$harness"
check "clean Wave A advances to Wave B" test "$(matrix_step pass pass clean 0)" = wave-b
check "contaminated Wave A retries once" test "$(matrix_step pass pass contaminated 0)" = retry
check "second contamination is cannot-determine" test "$(matrix_step pass pass contaminated 1)" = cannot-determine
check "retry cannot enter heap fallback" test "$(matrix_step heap-oome pass clean 1)" = stop

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

contamination_root=$scratch/contamination
mkdir -p "$contamination_root/results" "$contamination_root/receipts"
write_contamination_inputs() {
  local first_exact=$1 first_members=$2 first_unexpected=$3
  local second_exact=$4 second_members=$5 second_unexpected=$6
  printf '%s\n' "cgroup_members_exact=$first_exact" \
    "cgroup_member_count=$first_members" \
    "unexpected_cgroup_pid_count=$first_unexpected" \
    >"$contamination_root/receipts/coord.receipt"
  printf '%s\n' "cgroup_members_exact=$second_exact" \
    "cgroup_member_count=$second_members" \
    "unexpected_cgroup_pid_count=$second_unexpected" \
    >"$contamination_root/receipts/telemetry.receipt"
}
classify_contamination() {
  wave_contamination "$contamination_root" test-wave "$1" "$2" coord telemetry
}
write_contamination_inputs 1 2 0 1 2 0
check "unchanged host OOM counter and exact cgroups are clean" \
  test "$(classify_contamination 10 10)" = clean
check "one unrelated host OOM kill exceeds the zero threshold" \
  test "$(classify_contamination 10 11)" = contaminated
check "host OOM delta is recorded by the contamination producer" \
  grep -Fxq 'host_oom_kill_delta=1' \
    "$contamination_root/results/test-wave.contamination.receipt"
check "contamination receipt records the observed membership" \
  grep -Fxq 'first_cgroup_member_count=2' \
    "$contamination_root/results/test-wave.contamination.receipt"
check "contamination receipt records the zero thresholds" \
  grep -Fxq 'unexpected_cgroup_pid_max=0' \
    "$contamination_root/results/test-wave.contamination.receipt"
write_contamination_inputs 0 3 1 1 2 0
check "one unexpected cgroup PID contaminates Wave A" \
  test "$(classify_contamination 10 10)" = contaminated
write_contamination_inputs 0 1 0 1 2 0
check "incomplete cgroup membership contaminates Wave A" \
  test "$(classify_contamination 10 10)" = contaminated
write_contamination_inputs unknown -1 -1 1 2 0
check "unavailable cgroup membership is cannot-determine" \
  test "$(classify_contamination 10 10)" = cannot-determine
write_contamination_inputs 1 2 0 1 2 0
check "a receding host OOM counter is cannot-determine" \
  test "$(classify_contamination 11 10)" = cannot-determine

receipts=$scratch/receipts
mkdir -p "$receipts" "$scratch/results"
printf '%s\n' role=coordination classification=pass memory_peak=2500000000 cgroup_members_exact=1 \
  >"$receipts/coord-blue.receipt"
printf '%s\n' role=coordination classification=pass memory_peak=2600000000 \
  >"$receipts/coord-green.receipt"
printf '%s\n' role=telemetry classification=pass memory_peak=1400000000 cgroup_members_exact=1 \
  >"$receipts/telemetry-blue.receipt"
printf '%s\n' role=telemetry classification=pass memory_peak=1500000000 \
  >"$receipts/telemetry-green.receipt"
printf '%s\n' role=coordination classification=pass memory_peak=9000000000 \
  decision_sample=excluded-contamination \
  >"$receipts/coord-discovery.receipt"
printf '%s\n' role=telemetry classification=pass memory_peak=8000000000 \
  decision_sample=excluded-contamination \
  >"$receipts/telemetry-discovery.receipt"
report=$scratch/report
"$harness" report "$receipts" >"$report"
check "zero host OOM delta and exact cgroups are clean" \
  test "$(wave_contamination "$scratch" inline-wave 7 7 coord-blue telemetry-blue)" = clean
check "host OOM delta contaminates Wave A" \
  test "$(wave_contamination "$scratch" inline-wave 7 8 coord-blue telemetry-blue)" = contaminated
check "contaminated Wave-A samples are excluded from decision math" \
  grep -Fxq 'coord_lower_bound_bytes=2600000000' "$report"
check "excluded telemetry sample does not raise the telemetry bound" \
  grep -Fxq 'telemetry_measured_peak_bytes=1500000000' "$report"
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
    /^cgroup_member_count=/{members++}
    /^unexpected_cgroup_pid_count=/{unexpected++}
    /^ready=/{ready++}
    /^work_complete=/{work++}
    /^decision_sample=/{decision++}
    END {
      exit argv == 6 && role == 6 && heap == 6 && cap == 6 &&
           exit_code == 6 && signal == 6 && oome == 6 && peak == 6 &&
           oom == 6 && kill == 6 && members == 6 && unexpected == 6 &&
           ready == 6 && work == 6 && decision == 6 ? 0 : 1
    }' "$mock_one"/cases/*/run.receipt
check "mock never launches systemd" test ! -e "$mock_one/systemd-run.called"

printf 'rotation-memory experiment harness: %d assertions passed\n' "$passes"
