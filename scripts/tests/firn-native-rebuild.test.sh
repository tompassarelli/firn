#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
WRAPPER="$REPO_ROOT/dotfiles/bin/firn"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP:?}"' EXIT

MOCK_REPO="$TEST_TMP/repo"
MOCK_NATIVE="$TEST_TMP/firn-native"
ARGV_LOG="$TEST_TMP/argv"
FALLBACK_LOG="$TEST_TMP/fallback"
mkdir -p "$MOCK_REPO/scripts"

cat > "$MOCK_NATIVE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" > "${FIRN_NATIVE_ARGV_LOG:?}"
exit "${FIRN_NATIVE_EXIT:?}"
EOF

cat > "$MOCK_REPO/scripts/firn-source-hash" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'racket-fallback\n' >> "${FIRN_FALLBACK_LOG:?}"
exit "${FIRN_FALLBACK_EXIT:-37}"
EOF

chmod +x "$MOCK_NATIVE" "$MOCK_REPO/scripts/firn-source-hash"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

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

set +e
FIRN_REPO="$MOCK_REPO" \
FIRN_NATIVE_BIN="$MOCK_NATIVE" \
FIRN_NATIVE_ARGV_LOG="$ARGV_LOG" \
FIRN_NATIVE_EXIT=23 \
"$WRAPPER" rebuild --skip-checks
status=$?
set -e
[ "$status" -eq 23 ] || fail "firn rebuild exit status was $status, expected 23"
assert_argv "$ARGV_LOG" rebuild --skip-checks

set +e
FIRN_REPO="$MOCK_REPO" \
FIRN_NATIVE_BIN="$MOCK_NATIVE" \
FIRN_NATIVE_ARGV_LOG="$ARGV_LOG" \
FIRN_NATIVE_EXIT=29 \
"$WRAPPER" host rebuild whiterabbit --skip-checks
status=$?
set -e
[ "$status" -eq 29 ] || fail "firn host rebuild exit status was $status, expected 29"
assert_argv "$ARGV_LOG" host rebuild whiterabbit --skip-checks

rm -f "${ARGV_LOG:?}"
set +e
FIRN_REPO="$MOCK_REPO" \
FIRN_NATIVE_BIN="$MOCK_NATIVE" \
FIRN_NATIVE_ARGV_LOG="$ARGV_LOG" \
FIRN_FALLBACK_LOG="$FALLBACK_LOG" \
"$WRAPPER" status
status=$?
set -e
[ "$status" -eq 37 ] || fail "firn status fallback exit status was $status, expected 37"
[ ! -e "$ARGV_LOG" ] || fail "firn status was intercepted by the native executable"
[ "$(wc -l < "$FALLBACK_LOG")" -eq 1 ] || fail "firn status did not reach the Racket fallback"

set +e
FIRN_REPO="$MOCK_REPO" \
FIRN_NATIVE_BIN="$TEST_TMP/missing-native" \
FIRN_FALLBACK_LOG="$FALLBACK_LOG" \
"$WRAPPER" rebuild
status=$?
set -e
[ "$status" -eq 37 ] || fail "missing native rebuild fallback exit status was $status, expected 37"
[ "$(wc -l < "$FALLBACK_LOG")" -eq 2 ] || fail "missing native rebuild did not reach the Racket fallback"

printf 'firn native rebuild dispatch: ok\n'
