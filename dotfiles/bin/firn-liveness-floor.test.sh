#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo/dotfiles/bin/firn-liveness-floor"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-liveness-floor.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  rm -rf "${scratch:?}"
  exit "$status"
}
trap cleanup EXIT

die() { printf 'firn-liveness-floor-test: %s\n' "$*" >&2; exit 1; }
ok() { printf 'PASS %s\n' "$1"; }

fixture_repo="$scratch/repo"
fixture_bin="$scratch/bin"
fixture_candidate="$scratch/candidate"
mkdir -p "$fixture_repo" "$fixture_bin" "$fixture_candidate/bin"
git init -q -b main "$fixture_repo"
git -C "$fixture_repo" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty -qm base

write_tool() {
  local name="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "$@" >"$fixture_bin/$name"
  chmod +x "$fixture_bin/$name"
}

write_tool agents 'test "${LIVENESS_CASE:-ok}" != missing-hook || exit 1' \
  'echo "checked: hooks"'
write_tool firn \
  'if [ "${1:-}" = repo ]; then test "${LIVENESS_CASE:-ok}" != skew || exit 1; echo "first-party input ok"; exit 0; fi' \
  'test "${LIVENESS_CASE:-ok}" != silent-cli || exit 0' \
  'echo whiterabbit'
cp "$fixture_bin/firn" "$fixture_candidate/bin/firn"
write_tool nix \
  'test "${LIVENESS_CASE:-ok}" != build-failure || exit 1' \
  'if [[ "$*" == *firn-native* ]]; then printf "%s\n" "${LIVENESS_CANDIDATE:?}"; ' \
  'else printf "/nix/store/fake-toplevel\n"; fi'

run_case() {
  local name="$1" expected="$2"
  local status=0
  set +e
  LIVENESS_CASE="$name" LIVENESS_CANDIDATE="$fixture_candidate" \
    FIRN_LIVENESS_REPO="$fixture_repo" \
    FIRN_LIVENESS_GIT=git FIRN_LIVENESS_NIX="$fixture_bin/nix" \
    FIRN_LIVENESS_CURRENT_FIRN="$fixture_bin/firn" \
    FIRN_LIVENESS_AGENTS="$fixture_bin/agents" \
    FIRN_LIVENESS_STATE_DIR="$scratch/state-$name" \
    "$script" >"$scratch/$name.out" 2>"$scratch/$name.err"
  status=$?
  set -e
  [[ "$status" == "$expected" ]] || die "$name: expected $expected, got $status"
}

run_case ok 0
rg -F 'OK ' "$scratch/ok.out" >/dev/null || die 'success did not report its revision'
python3 - "$scratch/state-ok/delivery-liveness.json" <<'PY'
import json, sys
fact = json.load(open(sys.argv[1]))
assert fact["version"] == 1
assert fact["buildable"] is True
assert fact["failing_check"] is None
assert len(fact["inputs"]["nixos_config"]) == 40
assert fact["freshness_seconds"] > 0
PY
test -s "$scratch/state-ok/delivery-liveness.json.sha256" \
  || die 'success did not write content identity'
ok success

for case_name in missing-hook skew silent-cli build-failure; do
  run_case "$case_name" 1
  python3 - "$scratch/state-$case_name/delivery-liveness.json" <<'PY'
import json, sys
fact = json.load(open(sys.argv[1]))
assert fact["buildable"] is False
assert isinstance(fact["failing_check"], str) and fact["failing_check"]
PY
  ok "$case_name"
done
