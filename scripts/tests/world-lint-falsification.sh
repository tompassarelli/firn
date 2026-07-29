#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
readonly REPO_ROOT
readonly WORLD="$REPO_ROOT/dotfiles/bin/world"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch:?}"' EXIT

mkdir -p "$scratch/canary/main"
git -C "$scratch/canary/main" init -q
git -C "$scratch/canary/main" config user.name world-test
git -C "$scratch/canary/main" config user.email world-test@example.invalid
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'printf "%s\n" /home/worldtest/code/north/main' # world:allow
} >"$scratch/canary/main/violation"
chmod +x "$scratch/canary/main/violation"
git -C "$scratch/canary/main" add violation
git -C "$scratch/canary/main" commit -qm fixture

roots="$HOME/code/nixos-config/main:$HOME/code/north/main:$HOME/code/fram/main:$HOME/code/beagle/main:$scratch/canary/main" # world:allow
set +e
output="$(
  WORLD_MANIFEST_PATH="$scratch/missing-manifest.env" \
  WORLD_LINT_ROOTS="$roots" \
  WORLD_LINT_FAIL=1 \
  "$WORLD" check --lint 2>&1
)"
status=$?
set -e

(( status != 0 )) || {
  printf 'FAIL: production lint returned success for a planted violation\n%s\n' "$output" >&2
  exit 1
}
grep -F 'canary/violation' <<<"$output" >/dev/null || {
  printf 'FAIL: planted violation was not reported\n%s\n' "$output" >&2
  exit 1
}
grep -Eq 'topology-refs: [0-9]+ allowed, [1-9][0-9]* new' <<<"$output" || {
  printf 'FAIL: lint summary did not count the planted violation as new\n%s\n' "$output" >&2
  exit 1
}
printf 'PASS: production lint detected the planted scratch-repo violation\n'
