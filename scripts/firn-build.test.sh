#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_UNDER_TEST="${FIRN_BUILD_UNDER_TEST:-$HERE/firn-build}"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch:?}"' EXIT

route_repo="$scratch/route-repo"
route_beagle="$scratch/route-beagle"
route_bin="$scratch/route-bin"
route_calls="$scratch/route-calls"
route_builds="$scratch/route-builds"
mkdir -p "$route_repo/scripts" "$route_repo/hosts/test" \
  "$route_beagle/bin" "$route_bin"
cp "$BUILD_UNDER_TEST" "$route_repo/scripts/firn-build"
printf ':enabled [test]\n' >"$route_repo/hosts/test/enabled-tags.bnix"
: >"$route_calls"
: >"$route_builds"

cat >"$route_bin/firn" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'repo=%s|beagle=%s|cwd=%s|args=%s\n' \
  "${FIRN_REPO:-}" "${BEAGLE_PATH:-}" "$PWD" "$*" \
  >>"$CALL_LOG"
if [ "$*" = "${FAIL_MATCH:-}" ]; then
  exit "${FAIL_RC:-73}"
fi
SH
chmod +x "$route_bin/firn"

cat >"$route_beagle/bin/beagle-build-all" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BEAGLE_BUILD_LOG"
exit 91
SH
chmod +x "$route_beagle/bin/beagle-build-all"

run_route() {
  PATH="$route_bin:$PATH" \
    FIRN_REPO="$route_repo" \
    BEAGLE_PATH="$route_beagle" \
    CALL_LOG="$route_calls" \
    BEAGLE_BUILD_LOG="$route_builds" \
    FAIL_MATCH="${FAIL_MATCH:-}" \
    "$route_repo/scripts/firn-build"
}

success_output="$scratch/success-output"
run_route >"$success_output" 2>&1
expected_routes="$(printf \
  'repo=%s|beagle=%s|cwd=%s|args=tag resolve all+emit\nrepo=%s|beagle=%s|cwd=%s|args=flake-input resolve emit' \
  "$route_repo" "$route_beagle" "$route_repo" \
  "$route_repo" "$route_beagle" "$route_repo")"
[ "$(<"$route_calls")" = "$expected_routes" ]
grep -Fxq 'firn-build: nothing to rebuild.' "$success_output"
[ ! -s "$route_builds" ]

: >"$route_calls"
tag_failure_output="$scratch/tag-failure-output"
set +e
FAIL_MATCH='tag resolve all+emit' run_route >"$tag_failure_output" 2>&1
tag_failure_rc=$?
set -e
[ "$tag_failure_rc" -eq 1 ]
grep -Fxq 'firn-build: tag resolution failed; aborting before .nix regeneration' \
  "$tag_failure_output"
[ "$(wc -l <"$route_calls")" -eq 1 ]
grep -Fq '|args=tag resolve all+emit' "$route_calls"
if grep -Fq '|args=flake-input resolve emit' "$route_calls"; then
  exit 1
fi
[ ! -s "$route_builds" ]

: >"$route_calls"
flake_failure_output="$scratch/flake-failure-output"
set +e
FAIL_MATCH='flake-input resolve emit' run_route >"$flake_failure_output" 2>&1
flake_failure_rc=$?
set -e
[ "$flake_failure_rc" -eq 1 ]
grep -Fxq 'firn-build: flake-inputs resolution failed; aborting' \
  "$flake_failure_output"
[ "$(wc -l <"$route_calls")" -eq 2 ]
grep -Fq '|args=tag resolve all+emit' "$route_calls"
grep -Fq '|args=flake-input resolve emit' "$route_calls"
[ ! -s "$route_builds" ]

printf 'ok: firn-build routes preparation through native Firn\n'
