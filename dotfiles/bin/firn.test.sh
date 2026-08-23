#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-live-launcher-test.XXXXXX")"
cleanup() {
  rm -rf -- "${scratch:?}"
}
trap cleanup EXIT

home="$scratch/home"
beagle_path="$scratch/beagle-alt"
firn_repo="$scratch/firn-alt"
fake_bin="$scratch/bin"
mkdir -p "$home" "$beagle_path/bin" "$firn_repo/native" "$fake_bin"
printf '#lang beagle\n(ns firn.main)\n' >"$firn_repo/native/firn.bgl"
printf 'alpha\n' >"$firn_repo/marker"

cat >"$beagle_path/bin/beagle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BEAGLE_CALL\0' >>"$FAKE_BEAGLE_LOG"
printf '%s\0' "$BEAGLE_PATH" "$FIRN_REPO" "$@" >>"$FAKE_BEAGLE_LOG"
if [[ "${1:-}" != native-exe ]]; then
  exit 0
fi
out=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --out ]]; then
    out="$2"
    break
  fi
  shift
done
[[ -n "$out" ]]
marker="$(sed -n '1p' "$FIRN_REPO/marker")"
cat >"$out" <<INNER
#!/usr/bin/env bash
printf 'compiled:%s\\n' '$marker'
printf 'RUNTIME_CALL\\0' >>"\$FAKE_RUNTIME_LOG"
printf '%s\\0' "\$BEAGLE_PATH" "\$FIRN_REPO" "\$@" >>"\$FAKE_RUNTIME_LOG"
INNER
chmod +x "$out"
EOF
chmod +x "$beagle_path/bin/beagle"

for command in nix nix-store; do
  cat >"$fake_bin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"$NIX_TRIPWIRE_LOG"
exit 97
EOF
  chmod +x "$fake_bin/$command"
done

export HOME="$home"
export PATH="$fake_bin:$PATH"
export FAKE_BEAGLE_LOG="$scratch/beagle.log"
export FAKE_RUNTIME_LOG="$scratch/runtime.log"
export NIX_TRIPWIRE_LOG="$scratch/nix.log"

run_live() {
  BEAGLE_PATH="$beagle_path" FIRN_REPO="$firn_repo" \
    "$here/firn" repo validate
}

run_live_all() {
  BEAGLE_PATH="$beagle_path" FIRN_REPO="$firn_repo" \
    "$here/firn" repo validate all
}

run_live_explicit() {
  BEAGLE_PATH="$beagle_path" FIRN_REPO="$firn_repo" \
    "$here/firn" repo validate hosts/whiterabbit/configuration.bnix
}

run_live_chained() {
  BEAGLE_PATH="$beagle_path" FIRN_REPO="$firn_repo" \
    "$here/firn" repo validate tag enable terminal
}

[[ "$(run_live)" == "compiled:alpha" ]]
printf 'beta\n' >"$firn_repo/marker"
[[ "$(run_live)" == "compiled:beta" ]]
[[ "$(run_live_all)" == "compiled:beta" ]]
[[ "$(run_live_explicit)" == "compiled:beta" ]]
[[ "$(run_live_chained)" == "compiled:beta" ]]

python3 - "$scratch/beagle.log" "$scratch/runtime.log" "$beagle_path" "$firn_repo" <<'PY'
import pathlib
import sys

beagle_log = pathlib.Path(sys.argv[1])
runtime_log = pathlib.Path(sys.argv[2])
beagle_path = pathlib.Path(sys.argv[3])
firn_repo = pathlib.Path(sys.argv[4])


def records(path, marker):
    result = []
    current = None
    for field in path.read_bytes().split(b"\0"):
        if field == marker:
            current = []
            result.append(current)
        elif current is not None and field:
            current.append(field)
    return result


beagle_calls = records(beagle_log, b"BEAGLE_CALL")
runtime_calls = records(runtime_log, b"RUNTIME_CALL")
assert len(beagle_calls) == 5
assert len(runtime_calls) == 5

beagle_prefix = str(beagle_path).encode()
firn_prefix = str(firn_repo).encode()
narrow_sources = [
    str(beagle_path / "native-core/src/native/json.bgl").encode(),
    str(firn_repo / "native/schema_transaction.bgl").encode(),
    str(firn_repo / "native/schema_transaction_native.bgl").encode(),
]

for call in beagle_calls[:3]:
    assert call[:3] == [beagle_prefix, firn_prefix, b"native-exe"]
    entry_index = call.index(b"--entry")
    assert call[entry_index + 1] == b"firn.schema-transaction-native/-main"
    assert call[entry_index + 2:] == narrow_sources

for call in beagle_calls[3:]:
    assert call[:3] == [beagle_prefix, firn_prefix, b"native-exe"]
    entry_index = call.index(b"--entry")
    assert call[entry_index + 1] == b"firn.main/-main"
    aggregate_sources = call[entry_index + 2:]
    assert len(aggregate_sources) == 33
    assert aggregate_sources[0] == str(
        beagle_path / "native-core/src/beagle/datum_reader.bgl"
    ).encode()
    assert aggregate_sources[-1] == str(firn_repo / "native/firn.bgl").encode()

assert runtime_calls == [
    [beagle_prefix, firn_prefix, b"repo", b"validate"],
    [beagle_prefix, firn_prefix, b"repo", b"validate"],
    [beagle_prefix, firn_prefix, b"repo", b"validate", b"all"],
    [
        beagle_prefix,
        firn_prefix,
        b"repo",
        b"validate",
        b"hosts/whiterabbit/configuration.bnix",
    ],
    [
        beagle_prefix,
        firn_prefix,
        b"repo",
        b"validate",
        b"tag",
        b"enable",
        b"terminal",
    ],
]
PY

[[ ! -e "$NIX_TRIPWIRE_LOG" ]]

set +e
BEAGLE_PATH="$scratch/missing" FIRN_REPO="$firn_repo" \
  "$here/firn" repo validate >"$scratch/missing.stdout" 2>"$scratch/missing.stderr"
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]]
grep -Fq "firn: BEAGLE_PATH has no executable bin/beagle: $scratch/missing" \
  "$scratch/missing.stderr"
[[ ! -s "$scratch/missing.stdout" ]]
[[ ! -e "$NIX_TRIPWIRE_LOG" ]]

BEAGLE_PATH="$beagle_path" FAKE_BEAGLE_LOG="$scratch/beagle-command.log" \
  FIRN_REPO="$firn_repo" "$here/beagle" check sentinel.bgl >/dev/null
python3 - "$scratch/beagle-command.log" "$beagle_path" <<'PY'
import pathlib
import sys

fields = pathlib.Path(sys.argv[1]).read_bytes().split(b"\0")
assert fields[0] == b"BEAGLE_CALL"
assert fields[1] == sys.argv[2].encode()
assert b"check" in fields
assert b"sentinel.bgl" in fields
PY

printf 'firn-live-launcher: PASS\n'
