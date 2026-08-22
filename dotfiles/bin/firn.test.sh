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
printf '%s\0' "$BEAGLE_PATH" "$FIRN_REPO" "$@" >>"$FAKE_BEAGLE_LOG"
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

[[ "$(run_live)" == "compiled:alpha" ]]
printf 'beta\n' >"$firn_repo/marker"
[[ "$(run_live)" == "compiled:beta" ]]

python3 - "$scratch/beagle.log" "$scratch/runtime.log" "$beagle_path" "$firn_repo" <<'PY'
import pathlib
import sys

beagle_log, runtime_log, beagle_path, firn_repo = map(pathlib.Path, sys.argv[1:])
beagle_fields = beagle_log.read_bytes().split(b"\0")
runtime_fields = runtime_log.read_bytes().split(b"\0")
assert beagle_fields.count(str(beagle_path).encode()) == 2
assert beagle_fields.count(str(firn_repo).encode()) == 2
assert beagle_fields.count(b"native-exe") == 2
assert beagle_fields.count(b"firn.main/-main") == 2
assert runtime_fields.count(str(beagle_path).encode()) == 2
assert runtime_fields.count(str(firn_repo).encode()) == 2
assert runtime_fields.count(b"repo") == 2
assert runtime_fields.count(b"validate") == 2
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
assert fields[0] == sys.argv[2].encode()
assert b"check" in fields
assert b"sentinel.bgl" in fields
PY

printf 'firn-live-launcher: PASS\n'
