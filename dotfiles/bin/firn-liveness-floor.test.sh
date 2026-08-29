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
mkdir -p "$fixture_repo" "$fixture_bin"
git init -q -b main "$fixture_repo"
git -C "$fixture_repo" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty -qm base

write_tool() {
  local name="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "$@" >"$fixture_bin/$name"
  chmod +x "$fixture_bin/$name"
}

write_tool agents 'test "${1:-}" = status' \
  'test "${LIVENESS_CASE:-ok}" != missing-hook || exit 1' \
  'echo "status: hooks"'
write_tool north 'echo north'
write_tool firn \
  'if [ "${1:-}" = repo ]; then test "${2:-}" = pin-ancestry; test "$#" -eq 2; test "${LIVENESS_CASE:-ok}" != skew || exit 1; echo "first-party input ok"; exit 0; fi' \
  'test "${LIVENESS_CASE:-ok}" != silent-cli || exit 0' \
  'echo whiterabbit'
write_tool nix \
  'test "${LIVENESS_CASE:-ok}" != build-failure || exit 1' \
  'printf "/nix/store/fake-toplevel\n"'
write_tool python \
  'current_json=null; [[ -z "${LIVENESS_CURRENT:-}" ]] || printf -v current_json "\"%s\"" "$LIVENESS_CURRENT"' \
  'candidate_json=null; [[ -z "${LIVENESS_CANDIDATE:-}" ]] || printf -v candidate_json "\"%s\"" "$LIVENESS_CANDIDATE"' \
  'failing_json=null; [[ -z "${LIVENESS_FAILING_CHECK:-}" ]] || printf -v failing_json "\"%s\"" "$LIVENESS_FAILING_CHECK"' \
  'printf "{\"buildable\":%s,\"failing_check\":%s,\"firn\":{\"candidate\":%s,\"current\":%s},\"freshness_seconds\":%s,\"inputs\":{\"nixos_config\":\"%s\"},\"observed_at\":\"%s\",\"version\":1}\n" "$LIVENESS_BUILDABLE" "$failing_json" "$candidate_json" "$current_json" "$LIVENESS_FRESHNESS_SECONDS" "$LIVENESS_REVISION" "$LIVENESS_OBSERVED_AT" >"${2:?}"'

run_case() {
  local name="$1" expected="$2"
  local status=0
  set +e
  LIVENESS_CASE="$name" \
    FIRN_LIVENESS_REPO="$fixture_repo" \
    FIRN_LIVENESS_GIT=git FIRN_LIVENESS_NIX="$fixture_bin/nix" \
    FIRN_LIVENESS_CURRENT_FIRN="$fixture_bin/firn" \
    FIRN_LIVENESS_AGENTS="$fixture_bin/agents" \
    FIRN_LIVENESS_PYTHON="$fixture_bin/python" \
    NORTH_BIN="$fixture_bin/north" \
    FIRN_LIVENESS_STATE_DIR="$scratch/state-$name" \
    "$script" >"$scratch/$name.out" 2>"$scratch/$name.err"
  status=$?
  set -e
  if [[ "$status" != "$expected" ]]; then
    sed -n '1,160p' "$scratch/$name.out" >&2
    sed -n '1,160p' "$scratch/$name.err" >&2
    die "$name: expected $expected, got $status"
  fi
}

run_case ok 0
rg -F 'OK ' "$scratch/ok.out" >/dev/null || die 'success did not report its revision'
FACT_PATH="$scratch/state-ok/delivery-liveness.json" bun -e '
  const fact = await Bun.file(process.env.FACT_PATH).json();
  if (fact.version !== 1 || fact.buildable !== true
      || fact.failing_check !== null
      || fact.inputs.nixos_config.length !== 40
      || fact.freshness_seconds <= 0) throw new Error("invalid success fact");
'
test -s "$scratch/state-ok/delivery-liveness.json.sha256" \
  || die 'success did not write content identity'
(cd "$scratch/state-ok" && sha256sum --check delivery-liveness.json.sha256) >/dev/null \
  || die 'success content identity did not match the fact'
ok success

mkdir -p "$scratch/state-busy"
exec 9>"$scratch/state-busy/delivery-liveness.json.lock"
flock -n 9 || die 'fixture could not hold producer lock'
run_case busy 75
exec 9>&-
test ! -e "$scratch/state-busy/delivery-liveness.json" \
  || die 'overlapping producer replaced the current authority'
ok overlapping-producer

for case_name in missing-hook skew silent-cli build-failure; do
  run_case "$case_name" 1
  FACT_PATH="$scratch/state-$case_name/delivery-liveness.json" bun -e '
    const fact = await Bun.file(process.env.FACT_PATH).json();
    if (fact.buildable !== false || typeof fact.failing_check !== "string"
        || fact.failing_check.length === 0) throw new Error("invalid failure fact");
  '
  ok "$case_name"
done
