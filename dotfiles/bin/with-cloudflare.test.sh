#!/usr/bin/env bash
set -euo pipefail

SCRIPT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/with-cloudflare
TEST_DIR=$(mktemp -d)
cleanup() {
  find "$TEST_DIR" -mindepth 1 -delete
  rmdir "$TEST_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_gjoa_token() {
  [ "$CLOUDFLARE_API_TOKEN" = scoped-token ]
  [ -z "${CLOUDFLARE_API_KEY:-}" ]
  [ -z "${CLOUDFLARE_EMAIL:-}" ]
  [ "$CLOUDFLARE_ACCOUNT_ID" = f6e67447d76e54e8d0837de3e6b08341 ]
}
export -f assert_gjoa_token

printf '%s\n' scoped-token > "$TEST_DIR/cloudflare-gjoa-api-token"
printf '%s\n' global-key > "$TEST_DIR/cloudflare-global-api-key"
WITH_CLOUDFLARE_SECRET_DIR=$TEST_DIR \
  CLOUDFLARE_API_KEY=stale CLOUDFLARE_EMAIL=stale@example.invalid \
  "$SCRIPT" gjoa -- bash -c assert_gjoa_token || fail 'scoped Gjoa token'

find "$TEST_DIR" -type f -delete
printf '%s\n' global-key > "$TEST_DIR/cloudflare-global-api-key"
WITH_CLOUDFLARE_SECRET_DIR=$TEST_DIR \
  "$SCRIPT" gjoa -- bash -c '
    [ -z "${CLOUDFLARE_API_TOKEN:-}" ] &&
    [ "$CLOUDFLARE_API_KEY" = global-key ] &&
    [ "$CLOUDFLARE_EMAIL" = tom.passarelli@protonmail.com ] &&
    [ "$CLOUDFLARE_ACCOUNT_ID" = f6e67447d76e54e8d0837de3e6b08341 ]
  ' || fail 'global-key fallback'

WITH_CLOUDFLARE_SECRET_DIR=$TEST_DIR \
  CLOUDFLARE_ACCOUNT_ID=stale \
  "$SCRIPT" admin -- bash -c '
    [ "$CLOUDFLARE_API_KEY" = global-key ] &&
    [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]
  ' || fail 'admin profile'

find "$TEST_DIR" -type f -delete
if WITH_CLOUDFLARE_SECRET_DIR=$TEST_DIR "$SCRIPT" gjoa -- true >/dev/null 2>&1; then
  fail 'missing credential must fail'
fi
if WITH_CLOUDFLARE_SECRET_DIR=$TEST_DIR "$SCRIPT" unknown -- true >/dev/null 2>&1; then
  fail 'unknown profile must fail'
fi

printf 'ok   with-cloudflare profiles and precedence\n'
