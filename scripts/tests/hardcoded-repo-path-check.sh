#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
readonly REPO_ROOT
readonly CHECK="$REPO_ROOT/dotfiles/bin/hardcoded-repo-path-check"
expected_allowed="$(
  awk -F'\t' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $2 !~ /^[1-9][0-9]*$/ { exit 1 }
    { total += $2 }
    END { print total + 0 }
  ' "$REPO_ROOT/config/hardcoded-repo-paths.tsv"
)" || {
  printf 'FAIL: malformed hard-coded repository path allowlist: %s\n' \
    "$REPO_ROOT/config/hardcoded-repo-paths.tsv" >&2
  exit 1
}
[[ "$expected_allowed" =~ ^[1-9][0-9]*$ ]] || {
  printf 'FAIL: hard-coded repository path allowlist declares no references\n' >&2
  exit 1
}
readonly expected_allowed
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch:?}"' EXIT

caller_repo="$scratch/caller-repo"
caller_linked="$scratch/caller-linked"
mkdir -p "$caller_repo"
git -C "$caller_repo" init -q
git -C "$caller_repo" config user.name path-check-test
git -C "$caller_repo" config user.email path-check-test@example.invalid
printf 'caller\n' >"$caller_repo/tracked"
git -C "$caller_repo" add tracked
git -C "$caller_repo" commit -qm caller
git -C "$caller_repo" worktree add -q -b linked-check "$caller_linked"
caller_git_dir="$(git -C "$caller_linked" rev-parse --absolute-git-dir)"
caller_index="$(git -C "$caller_linked" rev-parse --git-path index)"

mkdir -p "$scratch/canary/main"
git -C "$scratch/canary/main" init -q
git -C "$scratch/canary/main" config user.name path-check-test
git -C "$scratch/canary/main" config user.email path-check-test@example.invalid
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'printf "%s\n" /home/pathchecktest/code/north/main' # hardcoded-repo-path:allow
} >"$scratch/canary/main/violation"
chmod +x "$scratch/canary/main/violation"
git -C "$scratch/canary/main" add violation
git -C "$scratch/canary/main" commit -qm fixture

roots="$REPO_ROOT:$HOME/code/north/main:$HOME/code/beagle/main:$scratch/canary/main" # hardcoded-repo-path:allow
set +e
output="$(
  GIT_DIR="$caller_git_dir" \
  GIT_INDEX_FILE="$caller_index" \
  HARDCODED_REPO_PATH_CHECK_ROOTS="$roots" \
    "$CHECK" 2>&1
)"
status=$?
set -e

(( status == 1 )) || {
  printf 'FAIL: expected one planted path violation, got status %d\n%s\n' \
    "$status" "$output" >&2
  exit 1
}
grep -F 'canary/violation' <<<"$output" >/dev/null || {
  printf 'FAIL: planted violation was not reported\n%s\n' "$output" >&2
  exit 1
}
grep -F "hardcoded-repo-path-check: $expected_allowed allowed, 1 new" \
  <<<"$output" >/dev/null || {
  printf 'FAIL: canonical inventory or planted-violation count changed\n%s\n' \
    "$output" >&2
  exit 1
}
printf 'PASS: one scan ignored caller Git state, covered the canonical inventory, and detected the planted violation\n'
