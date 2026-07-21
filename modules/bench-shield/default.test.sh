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
mkdir -p "$FAKE_ROOT" "$FAKE_BIN"

# Exercise the generated program, not a hand-maintained test copy. Nix indents
# the shell body and escapes shell interpolation as two single quotes + `${`.
in_script=0
end_script=0
root_gate_replaced=0
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
  # This is a literal generated-program line, not an expression to expand here.
  # shellcheck disable=SC2016
  if [[ "$line" == 'if [[ "$COMMAND" =~ ^(on|off)$ ]] && (( EUID != 0 )); then' ]]; then
    line='if false; then'
    root_gate_replaced=1
  fi
  replacement="$SCRATCH/state"
  line="${line//\/run\/bench-shield/$replacement}"
  printf '%s\n' "$line" >> "$SCRIPT"
done < "$REPO/modules/bench-shield/default.nix"
(( in_script ))
(( end_script ))
(( root_gate_replaced ))
if grep -Fq /run/bench-shield "$SCRIPT"; then
  echo "test extraction retained the live bench-shield state path" >&2
  exit 1
fi
chmod +x "$SCRIPT"
bash -n "$SCRIPT"

cat > "$FAKE_BIN/nproc" <<'EOF'
#!/usr/bin/env bash
printf '24\n'
EOF

cat > "$FAKE_BIN/taskset" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -c ]]
shift 2
exec "$@"
EOF

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_ROOT:?}"
case "$1" in
  show)
    unit="${@: -1}"
    if [[ -f "$FAKE_ROOT/failures/fail-show-$unit" ]]; then
      exit 76
    fi
    cat "$FAKE_ROOT/units/$unit"
    ;;
  set-property)
    [[ "$2" == --runtime ]]
    unit="$3"
    value="${4#AllowedCPUs=}"
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
    if [[ "$value" != 0-15 && -f "$marker" ]]; then
      exit 75
    fi
    printf '%s' "$value" > "$FAKE_ROOT/units/$unit"
    ;;
  *)
    exit 64
    ;;
esac
EOF
chmod +x "$FAKE_BIN/nproc" "$FAKE_BIN/taskset" "$FAKE_BIN/systemctl"
export FAKE_ROOT
export PATH="$FAKE_BIN:$PATH"

units=(system.slice user.slice init.scope)

plant_original() {
  rm -rf "${FAKE_ROOT:?}/units" "${FAKE_ROOT:?}/expected" "${FAKE_ROOT:?}/failures" "${RUNTIME_STATE:?}"
  rm -f "${RUNTIME_LOCK:?}"
  mkdir -p "$FAKE_ROOT/units" "$FAKE_ROOT/expected" "$FAKE_ROOT/failures"
  printf '0-23' > "$FAKE_ROOT/units/system.slice"
  printf '0-7,16-23' > "$FAKE_ROOT/units/user.slice"
  printf '0-3 8-11' > "$FAKE_ROOT/units/init.scope"
  cp "$FAKE_ROOT/units/system.slice" "$FAKE_ROOT/expected/system.slice"
  cp "$FAKE_ROOT/units/user.slice" "$FAKE_ROOT/expected/user.slice"
  cp "$FAKE_ROOT/units/init.scope" "$FAKE_ROOT/expected/init.scope"
}

assert_original() {
  local unit
  for unit in "${units[@]}"; do
    cmp -s "$FAKE_ROOT/expected/$unit" "$FAKE_ROOT/units/$unit"
  done
}

assert_shielded() {
  local unit
  for unit in "${units[@]}"; do
    [[ "$(<"$FAKE_ROOT/units/$unit")" == 0-15 ]]
  done
}

# The first on snapshots all three non-default 24-CPU values before changing
# any unit. A repeated on must retain those originals; both off calls are safe.
plant_original
"$SCRIPT" on
assert_shielded
for unit in "${units[@]}"; do
  cmp -s "$FAKE_ROOT/expected/$unit" "$RUNTIME_STATE/$unit.allowed-cpus"
done
"$SCRIPT" on
assert_shielded
"$SCRIPT" off
assert_original
[[ ! -e "$RUNTIME_STATE" ]]
"$SCRIPT" off
assert_original

# A partial on failure rolls back every slice, including one already changed.
plant_original
: > "$FAKE_ROOT/failures/fail-mutate-user.slice"
if "$SCRIPT" on; then
  echo "expected partial on to fail" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# Snapshot failure precedes every mutation, so even the earlier units remain
# byte-for-byte unchanged and no incomplete snapshot is retained.
plant_original
: > "$FAKE_ROOT/failures/fail-show-init.scope"
if "$SCRIPT" on; then
  echo "expected snapshot failure" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# A benchmark interrupted by TERM still takes the managed run path through off.
plant_original
# The child expands PPID after taskset starts it; this test shell must not.
# shellcheck disable=SC2016
if "$SCRIPT" run -- bash -c 'kill -TERM "$PPID"; sleep 1'; then
  echo "expected interrupted benchmark to fail" >&2
  exit 1
fi
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# Even SIGKILL during mutation leaves a pending transaction that the next off
# can recover exactly; it never converts the original 0-23 allocation to 0-15.
plant_original
: > "$FAKE_ROOT/failures/kill-mutate-user.slice"
if "$SCRIPT" on; then
  echo "expected killed on to fail" >&2
  exit 1
fi
[[ "$(<"$RUNTIME_STATE/status")" == pending ]]
"$SCRIPT" off
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

# A persistent restore failure cannot discard the snapshots. Other units are
# still attempted, and a repeated off finishes cleanup once the fault clears.
plant_original
"$SCRIPT" on
: > "$FAKE_ROOT/failures/fail-restore-user.slice"
if "$SCRIPT" off; then
  echo "expected partial restore to fail" >&2
  exit 1
fi
cmp -s "$FAKE_ROOT/expected/system.slice" "$FAKE_ROOT/units/system.slice"
[[ "$(<"$FAKE_ROOT/units/user.slice")" == 0-15 ]]
cmp -s "$FAKE_ROOT/expected/init.scope" "$FAKE_ROOT/units/init.scope"
[[ "$(<"$RUNTIME_STATE/status")" == restore-pending ]]
rm -f "${FAKE_ROOT:?}/failures/fail-restore-user.slice"
"$SCRIPT" off
assert_original
[[ ! -e "$RUNTIME_STATE" ]]

printf 'ok: bench-shield exact restore\n'
