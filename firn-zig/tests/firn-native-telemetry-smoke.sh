#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
build="$repo_root/firn-zig/build.sh"
beagle_root="${BEAGLE_PATH:?firn native telemetry smoke requires BEAGLE_PATH}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-native-telemetry.XXXXXX")"
blocked_state="$scratch/blocked-state"

cleanup() {
  chmod u+rwx "$blocked_state" 2>/dev/null || true
  rm -rf "${scratch:?}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for tool in direnv jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

native_bin="$scratch/firn"
mock_repo="$scratch/repo"
mock_backend="$mock_repo/dotfiles/bin/firn"
mkdir -p "$mock_repo/dotfiles/bin" "$scratch/direnv"

cat > "$mock_backend" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\0' "$@" > "${MOCK_ARGV_LOG:?}"
printf '%s\0' \
  "${FIRN_DISABLE_NATIVE-}" \
  "${FIRN_TRACE_ID-}" \
  "${FIRN_TRACE_PATH-}" \
  "${FIRN_NIX_LOG_PATH-}" > "${MOCK_ENV_LOG:?}"
printf 'backend stdout: %s\n' "${MOCK_LABEL:?}"
printf 'backend stderr: %s\n' "${MOCK_LABEL:?}" >&2
exit "${MOCK_EXIT:?}"
EOF
chmod +x "$mock_backend"

DIRENV_CONFIG="$scratch/direnv" direnv allow "$beagle_root" >/dev/null
DIRENV_CONFIG="$scratch/direnv" \
BEAGLE_PATH="$beagle_root" \
FIRN_ZIG_OUT="$native_bin" \
  "$build"
[ -x "$native_bin" ] || fail "native Firn executable was not built"

assert_argv() {
  local log="$1"
  shift
  local -a actual=()
  local -a expected=("$@")
  local index

  mapfile -d '' -t actual < "$log"
  [ "${#actual[@]}" -eq "${#expected[@]}" ] \
    || fail "expected ${#expected[@]} argv values, got ${#actual[@]}"
  for ((index = 0; index < ${#expected[@]}; index++)); do
    [ "${actual[$index]}" = "${expected[$index]}" ] \
      || fail "argv[$index] expected '${expected[$index]}', got '${actual[$index]}'"
  done
}

read_backend_env() {
  local log="$1"
  local -a values=()

  mapfile -d '' -t values < "$log"
  [ "${#values[@]}" -eq 4 ] \
    || fail "expected 4 backend environment values, got ${#values[@]}"
  backend_disable_native="${values[0]}"
  backend_trace_id="${values[1]}"
  backend_trace_path="${values[2]}"
  backend_nix_log_path="${values[3]}"
}

assert_trace() {
  local trace_path="$1"
  local trace_id="$2"
  local nix_log_path="$3"
  local expected_status="$4"
  local expected_exit="$5"

  [ -s "$trace_path" ] || fail "trace was not written at $trace_path"
  jq -s -e \
    --arg trace_id "$trace_id" \
    --arg trace_path "$trace_path" \
    --arg nix_log_path "$nix_log_path" \
    --arg status "$expected_status" \
    --argjson exit_code "$expected_exit" \
    '
      length == 2
      and all(.[]; .schema == "firn.rebuild/v1")
      and .[0].event == "run_start"
      and .[1].event == "run_end"
      and .[0].trace_id == $trace_id
      and .[1].trace_id == $trace_id
      and .[0].trace_path == $trace_path
      and .[0].nix_log_path == $nix_log_path
      and (.[0].monotonic_ms | type) == "number"
      and (.[1].monotonic_ms | type) == "number"
      and .[0].monotonic_ms <= .[1].monotonic_ms
      and .[1].duration_ms == (.[1].monotonic_ms - .[0].monotonic_ms)
      and .[1].status == $status
      and .[1].exit_code == $exit_code
    ' "$trace_path" >/dev/null \
    || fail "trace schema or lifecycle assertion failed for $trace_path"
}

last_trace_id=""

run_traced_case() {
  local label="$1"
  local expected_exit="$2"
  local expected_status="$3"
  shift 3
  local state="$scratch/state-$label"
  local argv_log="$scratch/$label.argv"
  local env_log="$scratch/$label.env"
  local stdout_log="$scratch/$label.stdout"
  local stderr_log="$scratch/$label.stderr"
  local status

  mkdir -p "$state"
  set +e
  XDG_STATE_HOME="$state" \
  FIRN_REPO="$mock_repo" \
  MOCK_ARGV_LOG="$argv_log" \
  MOCK_ENV_LOG="$env_log" \
  MOCK_LABEL="$label" \
  MOCK_EXIT="$expected_exit" \
    "$native_bin" "$@" >"$stdout_log" 2>"$stderr_log"
  status=$?
  set -e

  [ "$status" -eq "$expected_exit" ] \
    || fail "$label exit status was $status, expected $expected_exit"
  assert_argv "$argv_log" "$@"
  grep -Fx "backend stdout: $label" "$stdout_log" >/dev/null \
    || fail "$label backend stdout was not preserved"
  grep -Fx "backend stderr: $label" "$stderr_log" >/dev/null \
    || fail "$label backend stderr was not preserved"

  read_backend_env "$env_log"
  [ "$backend_disable_native" = "1" ] \
    || fail "$label backend did not receive FIRN_DISABLE_NATIVE=1"
  [ -n "$backend_trace_id" ] || fail "$label backend trace id was empty"
  [ -n "$backend_trace_path" ] || fail "$label backend trace path was empty"
  [ -n "$backend_nix_log_path" ] || fail "$label backend Nix log path was empty"
  case "$backend_trace_path" in
    "$state"/*) ;;
    *) fail "$label trace path escaped XDG_STATE_HOME" ;;
  esac
  [ "$(dirname -- "$backend_trace_path")" = "$(dirname -- "$backend_nix_log_path")" ] \
    || fail "$label trace and Nix sidecar paths are not correlated"

  assert_trace "$backend_trace_path" "$backend_trace_id" \
    "$backend_nix_log_path" "$expected_status" "$expected_exit"
  last_trace_id="$backend_trace_id"
}

run_traced_case success 0 ok rebuild --skip-checks
success_trace_id="$last_trace_id"

run_traced_case failure 23 error host rebuild whiterabbit --skip-checks
[ "$last_trace_id" != "$success_trace_id" ] \
  || fail "success and failure runs reused a trace id"

mkdir -p "$blocked_state"
chmod 500 "$blocked_state"
blocked_argv="$scratch/blocked.argv"
blocked_env="$scratch/blocked.env"
set +e
XDG_STATE_HOME="$blocked_state" \
FIRN_REPO="$mock_repo" \
MOCK_ARGV_LOG="$blocked_argv" \
MOCK_ENV_LOG="$blocked_env" \
MOCK_LABEL=blocked \
MOCK_EXIT=31 \
  "$native_bin" rebuild --skip-checks >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 31 ] \
  || fail "unwritable-state run exited $status, expected backend status 31"
[ -s "$blocked_argv" ] || fail "unwritable-state run did not invoke the backend"
assert_argv "$blocked_argv" rebuild --skip-checks
read_backend_env "$blocked_env"
[ "$backend_disable_native" = "1" ] \
  || fail "unwritable-state backend did not receive FIRN_DISABLE_NATIVE=1"

printf 'firn native telemetry smoke: ok\n'
