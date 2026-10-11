#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
source_repo="$(cd "$here/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-family-runtime-test.XXXXXX")"
cleanup() { rm -rf -- "${scratch:?}"; }
trap cleanup EXIT

candidate_beagle="${BEAGLE_PATH:?set BEAGLE_PATH to the exact Beagle candidate}"
bash_path="$(command -v bash)"
producer_bun="${FIRN_BUN:-$HOME/.local/lib/firn/cli/current/bin/bun}"
clause_repo="${FIRN_CLAUSE_REPO:-$HOME/code/clause/main}" # hardcoded-repo-path:allow
real_git="$(command -v git)"
[[ -x "$producer_bun" ]]
real_runtime="$scratch/real-runtime"
PATH="$(dirname "$producer_bun"):$PATH" \
  FIRN_REPO="$source_repo" BEAGLE_PATH="$candidate_beagle" \
  FIRN_CLAUSE_REPO="$clause_repo" \
  FIRN_RUNTIME_ROOT="$real_runtime" \
  "$here/firn-runtime-update" >"$scratch/real-update.out"
FIRN_REPO="$source_repo" BEAGLE_PATH="$candidate_beagle" \
  FIRN_RUNTIME_ROOT="$real_runtime" \
  "$here/firn" host list all >"$scratch/real-hosts.out"
grep -Fxq '  whiterabbit' "$scratch/real-hosts.out"

printf 'firn-family-runtime: PASS\n'
