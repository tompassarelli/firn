#!/usr/bin/env bash
set -euo pipefail

shim_main() {
  local tool="${0##*/}"
  {
    printf '%s' "$tool"
    printf ' <%s>' "$@"
    printf '\n'
  } >>"${SAFE_PUSH_TEST_TRACE:?}"

  case "$tool:$1" in
    git:rev-parse)
      case "${2:-}" in
        --show-toplevel) printf '%s\n' "${SAFE_PUSH_TEST_REPO:?}" ;;
        --abbrev-ref)
          case "${3:-}" in
            HEAD) printf '%s\n' main ;;
            '@{upstream}') printf '%s\n' origin/main ;;
            *) return 2 ;;
          esac
          ;;
        -q)
          [ "${3:-}" = --verify ] || return 2
          case "${4:-}" in
            refs/tags/release-a) printf '%s\n' deadbeef ;;
            *) return 1 ;;
          esac
          ;;
        *) return 2 ;;
      esac
      ;;
    git:rev-list) printf '%s\n' deadbeef ;;
    git:branch) printf '%s\n' '  origin/main' ;;
    git:tag) printf '%s\n' 'release annotation' ;;
    git:push|git:fetch) ;;
    gitleaks:detect|gitleaks:dir) ;;
    *) return 2 ;;
  esac
}

if [ "${SAFE_PUSH_TEST_SHIM:-}" = 1 ]; then
  shim_main "$@"
  exit $?
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/safe-push"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/safe-push-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/repo"
trace="$scratch/trace"
: >"$trace"
ln -s "$(readlink -f "${BASH_SOURCE[0]}")" "$scratch/bin/git"
ln -s "$(readlink -f "${BASH_SOURCE[0]}")" "$scratch/bin/gitleaks"

case_output=''
case_status=0

run_case() {
  : >"$trace"
  set +e
  case_output="$(
    cd "$scratch/repo"
    SAFE_PUSH_TEST_SHIM=1 \
      SAFE_PUSH_TEST_TRACE="$trace" \
      SAFE_PUSH_TEST_REPO="$scratch/repo" \
      PATH="$scratch/bin:$PATH" \
      "$TARGET" "$@" 2>&1
  )"
  case_status=$?
  set -e
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  printf 'status: %s\noutput:\n%s\ntrace:\n' "$case_status" "$case_output" >&2
  sed 's/^/  /' "$trace" >&2
  exit 1
}

expect_status() {
  local expected="$1"
  if [ "$expected" = zero ]; then
    [ "$case_status" -eq 0 ] || fail "expected exit 0"
  else
    [ "$case_status" -ne 0 ] || fail "expected nonzero exit"
  fi
}

expect_output() {
  grep -Fq -- "$1" <<<"$case_output" || fail "missing output: $1"
}

expect_no_tool_calls() {
  [ ! -s "$trace" ] || fail 'argument path invoked git or gitleaks'
}

expect_no_mutation() {
  if grep -Eq '^git <(push|fetch)>' "$trace"; then
    fail 'dry-run reached a Git network mutation'
  fi
}

expect_no_push() {
  if grep -Eq '^git <push>' "$trace"; then
    fail 'dry-run reached a push'
  fi
}

for help_flag in -h --help; do
  run_case "$help_flag"
  expect_status zero
  expect_output 'Usage: safe-push'
  expect_no_tool_calls
done

for rejected in --wat main --force -f --force-with-lease --mirror --delete --prune; do
  run_case "$rejected"
  expect_status nonzero
  expect_no_tool_calls
done

run_case --tag
expect_status nonzero
expect_output '--tag needs a name'
expect_no_tool_calls

run_case --tag --dry-run
expect_status nonzero
expect_output '--tag needs a name'
expect_no_tool_calls

run_case --dry-run --dry-run
expect_status nonzero
expect_output 'duplicate --dry-run'
expect_no_tool_calls

run_case --tag release-a --tag release-b
expect_status nonzero
expect_output 'duplicate --tag'
expect_no_tool_calls

run_case --help --dry-run
expect_status nonzero
expect_output '--help cannot be combined'
expect_no_tool_calls

run_case --dry-run
expect_status zero
expect_output 'would push main -> origin'
expect_no_mutation
grep -Fq 'gitleaks <detect>' "$trace" || fail 'dry-run skipped the secret scan'

for tag_args in '--dry-run --tag release-a' '--tag release-a --dry-run'; do
  read -r -a parsed_args <<<"$tag_args"
  run_case "${parsed_args[@]}"
  expect_status zero
  expect_output 'would push tag release-a -> origin'
  expect_no_push
  grep -Fq 'gitleaks <dir>' "$trace" || fail 'tag dry-run skipped the annotation scan'
done

printf 'safe-push tests: PASS\n'
