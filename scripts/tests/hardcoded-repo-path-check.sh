#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
readonly REPO_ROOT
readonly WORLD="$REPO_ROOT/dotfiles/bin/world"
expected_allowed="$(
  awk -F'\t' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $2 !~ /^[1-9][0-9]*$/ { exit 1 }
    { total += $2 }
    END { print total + 0 }
  ' "$REPO_ROOT/config/world-allow.txt"
)" || {
  printf 'FAIL: malformed hard-coded repository path allowlist: %s\n' \
    "$REPO_ROOT/config/world-allow.txt" >&2
  exit 1
}
[[ "$expected_allowed" =~ ^[1-9][0-9]*$ ]] || {
  printf 'FAIL: hard-coded repository path allowlist declares no references\n' >&2
  exit 1
}
readonly expected_allowed
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch:?}"' EXIT

resolve_pre_commit() {
  local hook candidate

  if [[ -n "${PRE_COMMIT_BIN:-}" ]]; then
    [[ -x "$PRE_COMMIT_BIN" ]] || return 1
    printf '%s\n' "$PRE_COMMIT_BIN"
    return
  fi
  if candidate="$(command -v pre-commit 2>/dev/null)" &&
     [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return
  fi
  hook="$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/hooks/pre-commit"
  [[ -f "$hook" ]] || return 1
  candidate="$(awk '/^exec .*[/]pre-commit / { print $2; exit }' "$hook")"
  [[ -x "$candidate" ]] || return 1
  printf '%s\n' "$candidate"
}

pre_commit="$(resolve_pre_commit)" || {
  printf 'FAIL: pre-commit executable is unavailable\n' >&2
  exit 1
}
readonly pre_commit

caller_repo="$scratch/caller-repo"
caller_linked="$scratch/caller-linked"
mkdir -p "$caller_repo"
git -C "$caller_repo" init -q
git -C "$caller_repo" config user.name world-test
git -C "$caller_repo" config user.email world-test@example.invalid
printf 'caller\n' >"$caller_repo/tracked"
git -C "$caller_repo" add tracked
git -C "$caller_repo" commit -qm caller
git -C "$caller_repo" worktree add -q -b linked-hook "$caller_linked"
caller_git_dir="$(git -C "$caller_linked" rev-parse --absolute-git-dir)"
caller_index="$(git -C "$caller_linked" rev-parse --git-path index)"
canonical_roots="$REPO_ROOT:$("$WORLD" get repo.north):$("$WORLD" get repo.fram):$("$WORLD" get repo.beagle)" # world:allow
set +e
alternate_index_output="$(
  GIT_DIR="$caller_git_dir" \
  GIT_INDEX_FILE="$caller_index" \
  WORLD_MANIFEST_PATH="$scratch/missing-manifest.env" \
  WORLD_LINT_ROOTS="$canonical_roots" \
  WORLD_LINT_FAIL=1 \
    "$WORLD" check --lint 2>&1
)"
alternate_index_status=$?
set -e

(( alternate_index_status == 0 )) || {
  printf 'FAIL: caller linked-worktree Git environment narrowed the four-root path corpus\n%s\n' \
    "$alternate_index_output" >&2
  exit 1
}
grep -F "hardcoded-repo-paths: $expected_allowed allowed, 0 new" \
  <<<"$alternate_index_output" >/dev/null || {
  printf 'FAIL: linked-worktree Git environment did not scan the canonical inventory\n%s\n' \
    "$alternate_index_output" >&2
  exit 1
}
printf 'PASS: caller linked-worktree Git environment cannot narrow the four-root lint corpus\n'

set +e
hostile_output="$(
  cd "$REPO_ROOT"
  WORLD_MANIFEST_PATH="$scratch/missing-manifest.env" \
  WORLD_PRECOMMIT_LINT_ROOTS="$REPO_ROOT" \
    "$pre_commit" run hardcoded-repo-path-check --all-files --verbose 2>&1
)"
hostile_status=$?
set -e

(( hostile_status == 0 )) || {
  printf 'FAIL: hostile one-root environment narrowed the production hook\n%s\n' \
    "$hostile_output" >&2
  exit 1
}
grep -F "hardcoded-repo-paths: $expected_allowed allowed, 0 new" \
  <<<"$hostile_output" >/dev/null || {
  printf 'FAIL: production hook did not scan the four-root canonical inventory\n%s\n' \
    "$hostile_output" >&2
  exit 1
}
printf 'PASS: hostile one-root environment cannot narrow the production hook\n'

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
grep -Eq 'hardcoded-repo-paths: [0-9]+ allowed, [1-9][0-9]* new' <<<"$output" || {
  printf 'FAIL: lint summary did not count the planted violation as new\n%s\n' "$output" >&2
  exit 1
}
printf 'PASS: production lint detected the planted scratch-repo violation\n'
