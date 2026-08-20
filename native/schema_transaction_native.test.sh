#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'schema-transaction-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-schema-transaction.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'schema-transaction-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'schema-transaction-native: %s\n' "$*" >&2
  exit 1
}

for command in git rg timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

json="$beagle/native-core/src/native/json.bgl"
core="$repo/native/schema_transaction.bgl"
pure="$repo/native/schema_transaction_test.bgl"
native="$repo/native/schema_transaction_native.bgl"

printf 'schema-transaction-native: exact bundle check\n' >&2
timeout --foreground 180 "$beagle/bin/beagle" check --agent \
  "$json" "$core" "$pure" "$native" \
  >"$scratch/check.out" 2>"$scratch/check.err" \
  || {
    sed -n '1,260p' "$scratch/check.err" >&2
    die "exact bundle check failed"
  }
rg -x '0 errors( \([0-9]+ lint warnings hidden\))?' "$scratch/check.err" \
  >/dev/null \
  || die "exact bundle check did not report zero errors"

printf 'schema-transaction-native: building focused pure test\n' >&2
mkdir -p "$scratch/pure-artifacts"
timeout --foreground 700 "$beagle/bin/beagle" native-exe \
  --out "$scratch/schema-transaction-test" \
  --entry firn.schema-transaction-test/-main \
  --artifacts "$scratch/pure-artifacts" \
  "$json" "$core" "$pure" \
  >"$scratch/pure.build.out" 2>"$scratch/pure.build.err" \
  || {
    sed -n '1,260p' "$scratch/pure.build.err" >&2
    die "focused pure test compilation failed"
  }
[[ -x "$scratch/schema-transaction-test" ]] \
  || die "focused pure test executable is missing"

printf 'schema-transaction-native: focused pure policy fixtures\n' >&2
timeout --foreground 30 "$scratch/schema-transaction-test" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || {
    sed -n '1,200p' "$scratch/pure.out" >&2
    sed -n '1,200p' "$scratch/pure.err" >&2
    die "focused pure policy fixtures failed"
  }
[[ "$(rg -c '^PASS ' "$scratch/pure.out")" == "11" ]] \
  || die "focused pure policy fixture count changed"
[[ ! -s "$scratch/pure.err" ]] \
  || die "focused pure policy fixtures wrote stderr"

printf 'ok: native schema authority policy and transaction boundary are checked\n'
