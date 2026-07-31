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
route_racket_calls="$scratch/route-racket-calls"
mkdir -p "$route_repo/scripts" "$route_repo/dotfiles/bin" \
  "$route_repo/hosts/test" "$route_beagle/bin" "$route_beagle/beagle-lib" \
  "$route_bin"
cp "$BUILD_UNDER_TEST" "$route_repo/scripts/firn-build"
printf ':enabled [test]\n' >"$route_repo/hosts/test/enabled-tags.bnix"
: >"$route_calls"
: >"$route_builds"
: >"$route_racket_calls"

cat >"$route_repo/dotfiles/bin/firn" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
collects_root="${PLTCOLLECTS%%:*}"
[ "$(readlink -f "$collects_root/beagle")" = "$BEAGLE_PATH/beagle-lib" ]
if [[ "$PLTCOMPILEDROOTS" =~ (^|:)same(:|$) ]]; then
  exit 74
fi
printf 'disable=%s|repo=%s|beagle=%s|cwd=%s|args=%s\n' \
  "${FIRN_DISABLE_NATIVE:-}" "${FIRN_REPO:-}" "${BEAGLE_PATH:-}" "$PWD" "$*" \
  >>"$CALL_LOG"
if [ "$*" = "${FAIL_MATCH:-}" ]; then
  exit "${FAIL_RC:-73}"
fi
SH
chmod +x "$route_repo/dotfiles/bin/firn"

cat >"$route_beagle/bin/beagle-build-all" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BEAGLE_BUILD_LOG"
exit 91
SH
chmod +x "$route_beagle/bin/beagle-build-all"

cat >"$route_bin/racket" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RACKET_CALL_LOG"
exit 99
SH
chmod +x "$route_bin/racket"

run_route() {
  PATH="$route_bin:$PATH" \
    FIRN_REPO="$route_repo" \
    BEAGLE_PATH="$route_beagle" \
    CALL_LOG="$route_calls" \
    BEAGLE_BUILD_LOG="$route_builds" \
    RACKET_CALL_LOG="$route_racket_calls" \
    FAIL_MATCH="${FAIL_MATCH:-}" \
    "$route_repo/scripts/firn-build"
}

success_output="$scratch/success-output"
run_route >"$success_output" 2>&1
expected_routes="$(printf \
  'disable=1|repo=%s|beagle=%s|cwd=%s|args=tag resolve all+emit\ndisable=1|repo=%s|beagle=%s|cwd=%s|args=flake-input resolve emit' \
  "$route_repo" "$route_beagle" "$route_repo" \
  "$route_repo" "$route_beagle" "$route_repo")"
[ "$(<"$route_calls")" = "$expected_routes" ]
grep -Fxq 'firn-build: nothing to rebuild.' "$success_output"
[ ! -s "$route_builds" ]
[ ! -s "$route_racket_calls" ]

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

cache_repo="$scratch/cache-repo"
cache_beagle="$scratch/cache-beagle"
cache_share="$scratch/cache-share"
cache_builds="$scratch/cache-builds"
cache_execs="$scratch/cache-execs"
cache_beagle_builds="$scratch/cache-beagle-builds"
mkdir -p "$cache_repo/scripts/firn-cmds" "$cache_repo/dotfiles/bin" \
  "$cache_repo/hosts/test" "$cache_beagle/bin" "$cache_beagle/beagle-lib" \
  "$cache_share"
cp "$BUILD_UNDER_TEST" "$cache_repo/scripts/firn-build"
cp "$HERE/firn-build-bin" "$cache_repo/scripts/firn-build-bin"
cp "$HERE/firn-source-hash" "$cache_repo/scripts/firn-source-hash"
printf 'v1\n' >"$cache_repo/scripts/firn.rkt"
printf '#lang racket/base\n' >"$cache_repo/scripts/firn-cmds/fixture.rkt"
printf ':enabled [test]\n' >"$cache_repo/hosts/test/enabled-tags.bnix"
printf '{}\n' >"$cache_beagle/flake.nix"
printf '{}\n' >"$cache_beagle/flake.lock"
printf '#lang racket/base\n' >"$cache_beagle/beagle-lib/fixture.rkt"
: >"$cache_builds"
: >"$cache_execs"
: >"$cache_beagle_builds"

cat >"$cache_beagle/fake-racket" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = --version ]; then
  printf 'Welcome to Racket v9.1 [test].\n'
  exit 0
fi
source_file="$1"
shift
source_identity="$(<"$source_file")"
printf 'source_file=%s|source=%s|args=%s|disable=%s|repo=%s\n' \
  "$source_file" "$source_identity" "$*" "${FIRN_DISABLE_NATIVE:-}" "${FIRN_REPO:-}" \
  >>"$EXEC_LOG"
SH
chmod +x "$cache_beagle/fake-racket"

cat >"$cache_beagle/fake-raco" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'make scripts/firn.rkt')
    printf '%s\n' "${PLTCOMPILEDROOTS%%:*}" >>"$BUILD_LOG"
    ;;
  *)
    printf 'unexpected fake raco invocation: %s\n' "$*" >&2
    exit 97
    ;;
esac
SH
chmod +x "$cache_beagle/fake-raco"

cat >"$cache_beagle/bin/_beagle-racket" <<SH
RACKET='$cache_beagle/fake-racket'
RACO='$cache_beagle/fake-raco'
SH

cat >"$cache_beagle/bin/beagle-build-all" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BEAGLE_BUILD_LOG"
exit 91
SH
chmod +x "$cache_beagle/bin/beagle-build-all"

cache_env=(
  FIRN_REPO="$cache_repo"
  BEAGLE_PATH="$cache_beagle"
  BIN_DIR="$cache_repo/dotfiles/bin"
  SHARE_DIR="$cache_share"
  FIRN_RUNTIME_SHARE_DIR="$cache_share"
  BUILD_LOG="$cache_builds"
  EXEC_LOG="$cache_execs"
  BEAGLE_BUILD_LOG="$cache_beagle_builds"
)

env "${cache_env[@]}" "$cache_repo/scripts/firn-build-bin" >/dev/null
hash_v1="$(env "${cache_env[@]}" "$cache_repo/scripts/firn-source-hash")"
runtime_v1="$(find "$cache_share" -type l -name runtime -print -quit)"
[ -f "$runtime_v1/.complete" ]
[ "$(wc -l <"$cache_builds")" -eq 1 ]

env "${cache_env[@]}" "$cache_repo/scripts/firn-build" >/dev/null
[ "$(wc -l <"$cache_builds")" -eq 1 ]
[ "$(wc -l <"$cache_execs")" -eq 2 ]
grep -Fq "|source=v1|args=tag resolve all+emit|disable=1|repo=$cache_repo" \
  "$cache_execs"
grep -Fq "|source=v1|args=flake-input resolve emit|disable=1|repo=$cache_repo" \
  "$cache_execs"

printf 'v2\n' >"$cache_repo/scripts/firn.rkt"
hash_v2="$(env "${cache_env[@]}" "$cache_repo/scripts/firn-source-hash")"
[ "$hash_v1" != "$hash_v2" ]
env "${cache_env[@]}" "$cache_repo/scripts/firn-build" >/dev/null 2>&1
[ "$(wc -l <"$cache_builds")" -eq 2 ]
[ "$(wc -l <"$cache_execs")" -eq 4 ]
runtime_v2="$(find "$cache_share" -type l -name runtime ! -path "$runtime_v1" -print -quit)"
[ -f "$runtime_v2/.complete" ]
grep -Fq "|source=v2|args=tag resolve all+emit|disable=1|repo=$cache_repo" \
  "$cache_execs"
grep -Fq "|source=v2|args=flake-input resolve emit|disable=1|repo=$cache_repo" \
  "$cache_execs"

env "${cache_env[@]}" "$cache_repo/scripts/firn-build" >/dev/null
[ "$(wc -l <"$cache_builds")" -eq 2 ]
[ "$(wc -l <"$cache_execs")" -eq 6 ]
[ ! -s "$cache_beagle_builds" ]

printf 'ok: firn-build routes preparation through source-attested compiled Firn\n'
