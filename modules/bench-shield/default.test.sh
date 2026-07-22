#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/bench-shield-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
SCRIPT="$SCRATCH/bench-shield"
FAKE_ROOT="$SCRATCH/fake"
FAKE_BIN="$SCRATCH/bin"
RUNTIME_STATE="$SCRATCH/state"
RUNTIME_LOCK="$SCRATCH/state.lock"
RUN_LOCK="$SCRATCH/run.lock"
mkdir -p "$FAKE_ROOT" "$FAKE_BIN"

# Exercise the generated program, not a hand-maintained test copy. Nix indents
# the shell body and escapes shell interpolation as two single quotes + `${`.
in_script=0
end_script=0
root_gate_replacements=0
while IFS= read -r line; do
  if (( ! in_script )) && [[ "$line" == *'writeShellScriptBin "bench-shield"'* ]]; then
    in_script=1
    continue
  fi
  (( in_script )) || continue
  if [[ "$line" == "      '')" ]]; then
    end_script=1
    break
  fi
  line="${line#        }"
  line="${line//\'\'\$\{/\$\{}"
  # These literal generated-program lines are test-harness substitutions.
  # shellcheck disable=SC2016
  if [[ "$line" == 'if [[ "$COMMAND" =~ ^(on|off|status)$ ]] && (( EUID != 0 )); then' \
     || "$line" == 'if [[ "$COMMAND" == __run ]] && (( EUID != 0 )); then' ]]; then
    line='if false; then'
    ((root_gate_replacements += 1))
  fi
  line="${line//\/run\/bench-shield.run.lock/$RUN_LOCK}"
  line="${line//\/run\/bench-shield.lock/$RUNTIME_LOCK}"
  line="${line//\/run\/bench-shield/$RUNTIME_STATE}"
  printf '%s\n' "$line" >> "$SCRIPT"
done < "$REPO/modules/bench-shield/default.nix"
(( in_script ))
(( end_script ))
(( root_gate_replacements == 2 ))
if grep -Fq /run/bench-shield "$SCRIPT"; then
  echo "test extraction retained a live bench-shield runtime path" >&2
  exit 1
fi
chmod +x "$SCRIPT"
bash -n "$SCRIPT"

cat > "$FAKE_BIN/nproc" <<'EOF'
#!/usr/bin/env bash
[[ $# == 0 || ( $# == 1 && $1 == --all ) ]]
printf '24\n'
EOF

cat > "$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == -- ]] && shift
exec "$@"
EOF

cat > "$FAKE_BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_ROOT:?}"
unit= slice= allowed= uid= gid= workdir= run_path= run_home=
while (( $# )); do
  case "$1" in
    --unit=*) unit=${1#--unit=} ;;
    --slice=*) slice=${1#--slice=} ;;
    --property=AllowedCPUs=*) allowed=${1#--property=AllowedCPUs=} ;;
    --uid=*) uid=${1#--uid=} ;;
    --gid=*) gid=${1#--gid=} ;;
    --working-directory=*) workdir=${1#--working-directory=} ;;
    --setenv=PATH=*) run_path=${1#--setenv=PATH=} ;;
    --setenv=HOME=*) run_home=${1#--setenv=HOME=} ;;
    --) shift; break ;;
  esac
  shift
done
[[ "$slice" == benchshield.slice ]]
[[ "$allowed" == 16-23 || "$allowed" == 22-23 ]]
[[ "$uid" == "$(id -u)" && "$uid" != 0 ]]
[[ "$gid" == "$(id -g)" ]]
[[ "$workdir" == "$PWD" ]]
[[ -n "$unit" && -n "$run_path" ]]
printf '%s\n' "$unit" > "$FAKE_ROOT/last-run.unit"
printf '%s\n' "$slice" > "$FAKE_ROOT/last-run.slice"
printf '%s\n' "$allowed" > "$FAKE_ROOT/last-run.effective"
printf '%s\n' "$uid" > "$FAKE_ROOT/last-run.uid"
if [[ -f "$FAKE_ROOT/failures/fail-systemd-run" ]]; then
  exit 78
fi
cd "$workdir"
export PATH="$run_path" HOME="$run_home" BENCH_SHIELD_FAKE_EFFECTIVE_CPUS="$allowed"
exec "$@"
EOF

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_ROOT:?}"
command=$1
shift
case "$command" in
  show)
    property=
    unit=
    while (( $# )); do
      case "$1" in
        --property=*) property=${1#--property=} ;;
        --value|--) ;;
        *) unit=$1 ;;
      esac
      shift
    done
    if [[ -f "$FAKE_ROOT/failures/fail-show-$unit" ]]; then
      exit 76
    fi
    case "$property" in
      AllowedCPUs) cat "$FAKE_ROOT/units/$unit.allowed" ;;
      EffectiveCPUs) cat "$FAKE_ROOT/units/$unit.effective" ;;
      *) exit 65 ;;
    esac
    ;;
  set-property)
    [[ "$1" == --runtime ]]
    unit=$2
    value=${3#AllowedCPUs=}
    printf '%s\t%s\n' "$unit" "$value" >> "$FAKE_ROOT/set-property.log"
    marker="$FAKE_ROOT/failures/kill-mutate-$unit"
    if [[ "$value" == 0-15 && -f "$marker" ]]; then
      rm -f "${marker:?}"
      kill -KILL "$PPID"
      exit 137
    fi
    marker="$FAKE_ROOT/failures/fail-mutate-$unit"
    if [[ "$value" == 0-15 && -f "$marker" ]]; then
      rm -f "${marker:?}"
      exit 74
    fi
    marker="$FAKE_ROOT/failures/fail-restore-$unit"
    if [[ "$value" != 0-15 && "$unit" != benchshield.slice && -f "$marker" ]]; then
      exit 75
    fi
    mkdir -p "$FAKE_ROOT/units"
    printf '%s' "$value" > "$FAKE_ROOT/units/$unit.allowed"
    # Model systemd's cpuset behavior: a non-empty property changes the
    # effective mask, but clearing the property does not widen it by itself.
    if [[ -n "$value" ]]; then
      printf '%s' "$value" > "$FAKE_ROOT/units/$unit.effective"
    else
      : > "$FAKE_ROOT/units/$unit.allowed"
    fi
    ;;
  stop)
    unit=$1
    printf '%s\n' "$unit" >> "$FAKE_ROOT/stopped.log"
    ;;
  *)
    exit 64
    ;;
esac
EOF
chmod +x "$FAKE_BIN/nproc" "$FAKE_BIN/sudo" "$FAKE_BIN/systemd-run" "$FAKE_BIN/systemctl"
export FAKE_ROOT
export PATH="$FAKE_BIN:$PATH"

units=(system.slice user.slice init.scope)

reset_fake() {
  rm -rf "${FAKE_ROOT:?}/units" "${FAKE_ROOT:?}/expected" "${FAKE_ROOT:?}/failures" "${RUNTIME_STATE:?}"
  rm -f "${RUNTIME_LOCK:?}" "${RUN_LOCK:?}" "$FAKE_ROOT/set-property.log" "$FAKE_ROOT/stopped.log" "${FAKE_ROOT:?}"/last-run.*
  mkdir -p "$FAKE_ROOT/units" "$FAKE_ROOT/expected" "$FAKE_ROOT/failures"
  : > "$FAKE_ROOT/units/-.slice.allowed"
  printf '0-23' > "$FAKE_ROOT/units/-.slice.effective"
}

plant_explicit_original() {
  reset_fake
  printf '0-23' > "$FAKE_ROOT/units/system.slice.allowed"
  printf '0-23' > "$FAKE_ROOT/units/system.slice.effective"
  printf '0-7,16-23' > "$FAKE_ROOT/units/user.slice.allowed"
  printf '0-7,16-23' > "$FAKE_ROOT/units/user.slice.effective"
  printf '0-3 8-11' > "$FAKE_ROOT/units/init.scope.allowed"
  printf '0-3 8-11' > "$FAKE_ROOT/units/init.scope.effective"
  for unit in "${units[@]}"; do
    cp "$FAKE_ROOT/units/$unit.allowed" "$FAKE_ROOT/expected/$unit.allowed"
    cp "$FAKE_ROOT/units/$unit.effective" "$FAKE_ROOT/expected/$unit.effective"
  done
}

plant_empty_original() {
  reset_fake
  for unit in "${units[@]}"; do
    : > "$FAKE_ROOT/units/$unit.allowed"
    printf '0-23' > "$FAKE_ROOT/units/$unit.effective"
    cp "$FAKE_ROOT/units/$unit.allowed" "$FAKE_ROOT/expected/$unit.allowed"
    cp "$FAKE_ROOT/units/$unit.effective" "$FAKE_ROOT/expected/$unit.effective"
  done
}

assert_original() {
  local unit
  for unit in "${units[@]}"; do
    cmp -s "$FAKE_ROOT/expected/$unit.allowed" "$FAKE_ROOT/units/$unit.allowed"
    cmp -s "$FAKE_ROOT/expected/$unit.effective" "$FAKE_ROOT/units/$unit.effective"
  done
}

assert_shielded() {
  local unit
  for unit in "${units[@]}"; do
    [[ "$(<"$FAKE_ROOT/units/$unit.allowed")" == 0-15 ]]
    [[ "$(<"$FAKE_ROOT/units/$unit.effective")" == 0-15 ]]
  done
}

# The first on snapshots both masks before changing any unit. Repeated on keeps
# the originals, and off restores and verifies both configured/effective masks.
plant_explicit_original
"$SCRIPT" on
assert_shielded
for unit in "${units[@]}"; do
  cmp -s "$FAKE_ROOT/expected/$unit.allowed" "$RUNTIME_STATE/$unit.allowed-cpus"
  cmp -s "$FAKE_ROOT/expected/$unit.effective" "$RUNTIME_STATE/$unit.effective-cpus"
done
"$SCRIPT" on
assert_shielded
"$SCRIPT" off
assert_original
[[ ! -e "$RUNTIME_STATE" ]]
"$SCRIPT" off
assert_original

# Successful run requests a top-level reserved-core slice and launches the
# payload as the invoking user, then removes the unit/slice and restores masks.
plant_explicit_original
# The payload, not this harness, expands its UID and fake effective mask.
# shellcheck disable=SC2016
"$SCRIPT" run 2 -- bash -c 'printf "%s" "$(id -u)" > "$FAKE_ROOT/payload.uid"; printf "%s" "$BENCH_SHIELD_FAKE_EFFECTIVE_CPUS" > "$FAKE_ROOT/payload.affinity"'
[[ "$(<"$FAKE_ROOT/payload.uid")" == "$(id -u)" ]]
[[ "$(<"$FAKE_ROOT/payload.affinity")" == 22-23 ]]
[[ "$(<"$FAKE_ROOT/last-run.slice")" == benchshield.slice ]]
[[ "$(<"$FAKE_ROOT/last-run.uid")" == "$(id -u)" ]]
grep -Fxq benchshield.slice "$FAKE_ROOT/stopped.log"
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# A non-zero payload and a systemd-run launch failure both restore the host.
plant_explicit_original
if "$SCRIPT" run 2 -- bash -c 'exit 42'; then
  echo "expected failing payload to fail" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

plant_explicit_original
: > "$FAKE_ROOT/failures/fail-systemd-run"
if "$SCRIPT" run 2 -- true; then
  echo "expected systemd-run failure" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]
grep -Fxq benchshield.slice "$FAKE_ROOT/stopped.log"

# A benchmark interrupted by TERM still stops the transient slice and restores.
plant_explicit_original
# The child expands PPID after systemd-run starts it; this test shell must not.
# shellcheck disable=SC2016
if "$SCRIPT" run -- bash -c 'kill -TERM "$PPID"; sleep 1'; then
  echo "expected interrupted benchmark to fail" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]
grep -Fxq benchshield.slice "$FAKE_ROOT/stopped.log"

# A partial on failure rolls back every slice, including one already changed.
plant_explicit_original
: > "$FAKE_ROOT/failures/fail-mutate-user.slice"
if "$SCRIPT" on; then
  echo "expected partial on to fail" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# Snapshot failure precedes every mutation and leaves no incomplete snapshot.
plant_explicit_original
: > "$FAKE_ROOT/failures/fail-show-init.scope"
if "$SCRIPT" on; then
  echo "expected snapshot failure" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# SIGKILL during mutation leaves a transaction the next off recovers exactly.
plant_explicit_original
: > "$FAKE_ROOT/failures/kill-mutate-user.slice"
if "$SCRIPT" on; then
  echo "expected killed on to fail" >&2
  exit 1
fi
[[ "$(<"$RUNTIME_STATE/status")" == pending ]]
"$SCRIPT" off
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# A persistent restore failure retains snapshots and a repeated off finishes.
plant_explicit_original
"$SCRIPT" on
: > "$FAKE_ROOT/failures/fail-restore-user.slice"
if "$SCRIPT" off; then
  echo "expected partial restore to fail" >&2
  exit 1
fi
cmp -s "$FAKE_ROOT/expected/system.slice.allowed" "$FAKE_ROOT/units/system.slice.allowed"
[[ "$(<"$FAKE_ROOT/units/user.slice.allowed")" == 0-15 ]]
cmp -s "$FAKE_ROOT/expected/init.scope.allowed" "$FAKE_ROOT/units/init.scope.allowed"
[[ "$(<"$RUNTIME_STATE/status")" == restore-pending ]]
rm -f "${FAKE_ROOT:?}/failures/fail-restore-user.slice"
"$SCRIPT" off
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# Empty AllowedCPUs needs an explicit widening step before clearing. The fake
# models the real systemd behavior that originally left EffectiveCPUs stuck.
plant_empty_original
"$SCRIPT" on
"$SCRIPT" off
assert_original
[[ ! -e "$RUNTIME_STATE" ]]
for unit in "${units[@]}"; do
  awk -F '\t' -v unit="$unit" '$1 == unit { print $2 }' "$FAKE_ROOT/set-property.log" | tail -n 2 | diff -u - <(printf '0-23\n\n')
done

# Status never calls a blank property "off" while its effective cpuset is
# still narrow; it reports both masks and exits non-zero with a pointed health.
plant_empty_original
printf '0-21' > "$FAKE_ROOT/units/system.slice.effective"
if status_output=$("$SCRIPT" status); then
  echo "expected inconsistent effective CPU status to fail" >&2
  exit 1
fi
grep -Fq 'transaction=none' <<< "$status_output"
grep -Fq 'system.slice   AllowedCPUs= EffectiveCPUs=0-21' <<< "$status_output"
grep -Fq 'health=untracked-effective-cpu-restriction' <<< "$status_output"

plant_explicit_original
status_output=$("$SCRIPT" status)
grep -Fq 'health=ok' <<< "$status_output"

printf 'ok: bench-shield transient reserved-core run and verified restore\n'
