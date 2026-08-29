#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
beagle="${BEAGLE_PATH:?set BEAGLE_PATH to the exact Beagle candidate}"
bun="${FIRN_BUN:-$(command -v bun)}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codex-invocation-controller-test.XXXXXX")"
cleanup() { rm -rf -- "${scratch:?}"; }
trap cleanup EXIT

modules="$scratch/modules"
"$beagle/bin/beagle-build-all" \
  "$beagle/native-core/src/native/json.bjs" \
  "$repo/native/codex_invocation_controller.bjs" \
  "$repo/native/codex_invocation_controller_test.bjs" \
  --out "$modules"
mkdir -p "$modules/node_modules/beagle"
cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
  "$modules/node_modules/beagle/core.js"
cp -- "$beagle/beagle-lib/lib/beagle/host.js" \
  "$modules/node_modules/beagle/host.js"
printf '%s\n' '{"type":"module"}' >"$modules/node_modules/beagle/package.json"

CONTROLLER_TEST_MODULE="$modules/firn/codex-invocation-controller-test.js" \
  "$bun" --eval \
  'const module = await import(process.env.CONTROLLER_TEST_MODULE); process.exit(module["run-tests"]());'

client="$scratch/client.mjs"
cat >"$client" <<'EOF'
import { closeSync, readSync, writeFileSync, writeSync } from 'node:fs';
import { dlopen, FFIType, ptr } from 'bun:ffi';

const fd = Number(process.env.CODEX_CONTROL_EXPECTATION_FD);
const mode = Bun.argv[2];
writeFileSync(process.env.CLIENT_PID_PATH, `${process.pid}\n`);
if (mode === 'exit') process.exit(29);

const libc = dlopen('libc.so.6', {
  getsockopt: {
    args: [FFIType.i32, FFIType.i32, FFIType.i32, FFIType.ptr, FFIType.ptr],
    returns: FFIType.i32,
  },
});
const credentials = new Int32Array(3);
const credentialLength = new Uint32Array([credentials.byteLength]);
if (libc.symbols.getsockopt(fd, 1, 17, ptr(credentials), ptr(credentialLength)) !== 0
    || credentialLength[0] !== credentials.byteLength
    || credentials[0] !== process.ppid
    || credentials[1] !== process.geteuid()) {
  process.exit(81);
}

const writeAll = bytes => {
  let offset = 0;
  while (offset < bytes.byteLength) {
    offset += writeSync(fd, bytes, offset, bytes.byteLength - offset);
  }
};
const encodedFrame = value => {
  const payload = Buffer.from(JSON.stringify(value), 'utf8');
  const result = Buffer.allocUnsafe(payload.byteLength + 4);
  result.writeUInt32BE(payload.byteLength, 0);
  payload.copy(result, 4);
  return result;
};
const send = value => writeAll(encodedFrame(value));
const readExact = bytes => {
  let offset = 0;
  while (offset < bytes.byteLength) {
    const amount = readSync(fd, bytes, offset, bytes.byteLength - offset, null);
    if (amount === 0) throw new Error('unexpected EOF');
    offset += amount;
  }
};
const receive = () => {
  const header = Buffer.alloc(4);
  readExact(header);
  const payload = Buffer.alloc(header.readUInt32BE(0));
  readExact(payload);
  return JSON.parse(payload.toString('utf8'));
};

const challenge = '12345678-1234-4abc-8def-1234567890ab';
const handshake = {
  version: 'InvocationFirewallHandshake/v1',
  kind: 'challenge',
  challenge,
  consumer_pid: mode === 'bad-pid' ? process.pid + 1 : process.pid,
};
const digest = `sha256:${'a'.repeat(64)}`;
const shape = name => ({
  tool: { name, namespace: null },
  payload_kind: 'FUNCTION',
  schema_digest: digest,
});
const request = requestId => ({
  record: 'invocation',
  version: 'InvocationFirewallRequest/v1',
  request_id: requestId,
  scope: {
    session_id: 'session-1', turn_id: 'turn-1', actor: 'codex:/root', call_slot: 1,
  },
  catalog_digest: digest,
  emitted: shape('get_goal'),
  catalog: [shape('get_goal'), shape('wait')],
});

if (mode === 'silent') {
  setInterval(() => {}, 1000);
} else if (mode === 'pipeline') {
  writeAll(Buffer.concat([encodedFrame(handshake), encodedFrame(request('pipelined'))]));
  setInterval(() => {}, 1000);
} else {
  send(handshake);
  if (mode === 'bad-pid') setInterval(() => {}, 1000);
  const response = receive();
  if (response.version !== 'InvocationFirewallHandshake/v1'
      || response.kind !== 'response'
      || response.challenge !== challenge
      || response.controller_pid !== process.ppid
      || response.controller_uid !== process.geteuid()) {
    process.exit(82);
  }
  if (mode === 'malformed') {
    send({ record: 'invocation' });
    setInterval(() => {}, 1000);
  } else if (mode === 'oversized') {
    const header = Buffer.alloc(4);
    header.writeUInt32BE((1024 * 1024) + 1, 0);
    writeAll(header);
    setInterval(() => {}, 1000);
  } else if (mode === 'partial-timeout' || mode === 'partial-eof') {
    const header = Buffer.alloc(4);
    header.writeUInt32BE(100, 0);
    writeAll(Buffer.concat([header, Buffer.from('{')]));
    if (mode === 'partial-eof') closeSync(fd);
    setInterval(() => {}, 1000);
  } else if (mode === 'eof') {
    closeSync(fd);
    setInterval(() => {}, 1000);
  } else if (mode === 'signal') {
    writeFileSync(process.env.CLIENT_READY_PATH, 'ready\n');
    setInterval(() => {}, 1000);
  } else {
    send(request('request-1'));
    const first = receive();
    if (first.record !== 'no_expectation'
        || first.version !== 'ControlExpectation/v2'
        || first.request_id !== 'request-1') {
      process.exit(83);
    }
    if (mode === 'replay') {
      send(request('request-1'));
      setInterval(() => {}, 1000);
    } else {
      send(request('request-2'));
      const second = receive();
      if (second.request_id !== 'request-2') process.exit(84);
      process.exit(23);
    }
  }
}
EOF

host="$repo/native/codex_invocation_controller_host.mjs"
protocol="$modules/firn/codex-invocation-controller.js"

assert_reaped() {
  local path="$1" pid
  [[ -s "$path" ]]
  pid="$(<"$path")"
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then return 0; fi
    sleep 0.05
  done
  printf 'client process was not reaped: %s\n' "$pid" >&2
  return 1
}

run_case() {
  local mode="$1" expected="$2" expected_error="${3:-}" status
  local pid_path="$scratch/$mode.pid"
  set +e
  CLIENT_PID_PATH="$pid_path" \
    CODEX_INVOCATION_CONTROLLER_MODULE="$protocol" \
    "$bun" "$host" "$bun" "$client" "$mode" \
    >"$scratch/$mode.out" 2>"$scratch/$mode.err"
  status=$?
  set -e
  if [[ "$status" -ne "$expected" ]]; then
    printf '%s: expected status %s, observed %s\n' "$mode" "$expected" "$status" >&2
    cat "$scratch/$mode.err" >&2
    return 1
  fi
  if [[ -n "$expected_error" ]]; then
    grep -Fq "$expected_error" "$scratch/$mode.err"
  fi
  assert_reaped "$pid_path"
}

run_case success 23
run_case exit 29
run_case silent 70 'exchange timeout'
run_case bad-pid 70 'invalid handshake challenge'
run_case malformed 70 'invalid invocation request'
run_case oversized 70 'invalid frame length'
run_case replay 70 'replayed invocation request'
run_case pipeline 70 'out-of-order pipelined frame'
run_case partial-timeout 70 'exchange timeout'
run_case partial-eof 70 'partial frame EOF'
run_case eof 70 'unexpected channel EOF'

signal_pid="$scratch/signal.pid"
signal_ready="$scratch/signal.ready"
CLIENT_PID_PATH="$signal_pid" CLIENT_READY_PATH="$signal_ready" \
  CODEX_INVOCATION_CONTROLLER_MODULE="$protocol" \
  "$bun" "$host" "$bun" "$client" signal \
  >"$scratch/signal.out" 2>"$scratch/signal.err" &
controller_pid=$!
for _ in {1..40}; do
  [[ -s "$signal_ready" ]] && break
  sleep 0.05
done
[[ -s "$signal_ready" ]]
kill -TERM "$controller_pid"
set +e
wait "$controller_pid"
signal_status=$?
set -e
[[ "$signal_status" -eq 143 ]]
assert_reaped "$signal_pid"

launcher_real="$scratch/codex-real"
launcher_controller="$scratch/codex-controller"
cat >"$launcher_real" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"$REAL_TRACE"
exit 37
EOF
cat >"$launcher_controller" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"$LAUNCH_TRACE"
exec "$@"
EOF
chmod +x "$launcher_real" "$launcher_controller"

launcher_home="$scratch/launcher-home"
native_profile="$launcher_home/.local/state/north/profiles/codex-native"
mkdir -p "$native_profile"
printf '%s\n' 'model = "fixture"' >"$native_profile/config.toml"
printf '%s\n' '{}' >"$native_profile/auth.json"

run_launcher() {
  local launcher="$1" launch_trace="$2" real_trace="$3" status
  shift 3
  set +e
  env -u NORTH_SLICE_ENTERED -u NORTH_SLICE_MARK \
    HOME="$launcher_home" XDG_RUNTIME_DIR= NORTH_NO_SLICE=1 \
    CODEX_HOME="$launcher_home/managed-profile" \
    CODEX_RUNTIME="$launcher_real" \
    CODEX_INVOCATION_CONTROLLER="$launcher_controller" \
    LAUNCH_TRACE="$launch_trace" REAL_TRACE="$real_trace" \
    bash "$launcher" "$@" >"$launch_trace.out" 2>"$launch_trace.err"
  status=$?
  set -e
  [[ "$status" -eq 37 ]]
  [[ -s "$launch_trace" && -e "$real_trace" ]]
}

managed_launch_trace="$scratch/managed-launch.trace"
managed_real_trace="$scratch/managed-real.trace"
run_launcher "$repo/dotfiles/bin/codex" \
  "$managed_launch_trace" "$managed_real_trace" alpha 'two words'
mapfile -d '' -t managed_launch_args <"$managed_launch_trace"
mapfile -d '' -t managed_real_args <"$managed_real_trace"
[[ "${#managed_launch_args[@]}" -ge 3 ]]
[[ "${#managed_real_args[@]}" -ge 2 ]]
[[ "${managed_launch_args[0]}" == "$launcher_real" ]]
[[ "${managed_launch_args[-2]}" == alpha ]]
[[ "${managed_launch_args[-1]}" == 'two words' ]]
[[ "${managed_real_args[-2]}" == alpha ]]
[[ "${managed_real_args[-1]}" == 'two words' ]]

native_launch_trace="$scratch/native-launch.trace"
native_real_trace="$scratch/native-real.trace"
run_launcher "$repo/dotfiles/bin/codex-native" \
  "$native_launch_trace" "$native_real_trace" alpha 'two words'
mapfile -d '' -t native_launch_args <"$native_launch_trace"
mapfile -d '' -t native_real_args <"$native_real_trace"
[[ "${#native_launch_args[@]}" -eq 7 ]]
[[ "${native_launch_args[0]}" == "$launcher_real" ]]
[[ "${native_launch_args[1]}" == -c ]]
[[ "${native_launch_args[2]}" == agents.max_concurrent_threads_per_session=64 ]]
[[ "${native_launch_args[3]}" == --add-dir ]]
[[ "${native_launch_args[4]}" == /home/tom/code ]]
[[ "${native_launch_args[5]}" == alpha ]]
[[ "${native_launch_args[6]}" == 'two words' ]]
[[ "${#native_real_args[@]}" -eq 6 ]]
[[ "${native_real_args[0]}" == -c ]]
[[ "${native_real_args[1]}" == agents.max_concurrent_threads_per_session=64 ]]
[[ "${native_real_args[2]}" == --add-dir ]]
[[ "${native_real_args[3]}" == /home/tom/code ]]
[[ "${native_real_args[4]}" == alpha ]]
[[ "${native_real_args[5]}" == 'two words' ]]

assert_missing_controller() {
  local launcher="$1" diagnostic="$2" status
  set +e
  env -u NORTH_SLICE_ENTERED -u NORTH_SLICE_MARK \
    HOME="$launcher_home" XDG_RUNTIME_DIR= NORTH_NO_SLICE=1 \
    CODEX_HOME="$launcher_home/managed-profile" \
    CODEX_RUNTIME="$launcher_real" \
    CODEX_INVOCATION_CONTROLLER="$scratch/missing-controller" \
    bash "$launcher" >"$scratch/missing-controller.out" \
    2>"$scratch/missing-controller.err"
  status=$?
  set -e
  [[ "$status" -eq 127 ]]
  [[ ! -s "$scratch/missing-controller.out" ]]
  grep -Fxq "$diagnostic" "$scratch/missing-controller.err"
}

assert_missing_controller "$repo/dotfiles/bin/codex" \
  'codex: invocation controller is unavailable; run firn-runtime-update full'
assert_missing_controller "$repo/dotfiles/bin/codex-native" \
  'codex-native: invocation controller is unavailable; run firn-runtime-update full'

printf 'codex-invocation-controller: PASS\n'
