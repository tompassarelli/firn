#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-repo-build-family.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'repo-build-family: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'repo-build-family: %s\n' "$*" >&2
  exit 1
}

timeout --foreground 60 bun \
  "$repo/native/repo_build_family_test_host.mjs" \
  >"$scratch/scenarios.out" 2>"$scratch/scenarios.err" \
  || {
    sed -n '1,240p' "$scratch/scenarios.err" >&2
    die "repo-build policy scenarios failed"
  }

galileo="galileo"
[[ -x "${FIRN_RUNTIME_BIN:-}/galileo" ]] && galileo="$FIRN_RUNTIME_BIN/galileo"
command -v "$galileo" >/dev/null \
  || die "galileo is not on PATH or in FIRN_RUNTIME_BIN"
(cd "$repo" && timeout --foreground 120 "$galileo" check) \
  >"$scratch/budget.out" 2>"$scratch/budget.err" \
  || {
    sed -n '1,240p' "$scratch/budget.out" "$scratch/budget.err" >&2
    die "galileo check boot-coupling budget failed"
  }

printf 'ok: real repository boot-coupling budget and policy checks pass\n'
