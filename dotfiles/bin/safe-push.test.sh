#!/usr/bin/env bash
set -euo pipefail

shim_main() {
  local tool="${0##*/}"
  {
    printf '%s' "$tool"
    printf ' <%s>' "$@"
    printf '\n'
  } >>"${SAFE_PUSH_TEST_TRACE:?}"

  if [[ "$tool" == gitleaks && -n "${SAFE_PUSH_TEST_REAL_RACE:-}" \
        && ! -s "${SAFE_PUSH_TEST_STATE:?}" ]]; then
    case "$SAFE_PUSH_TEST_REAL_RACE" in
      branch)
        git -C "${SAFE_PUSH_TEST_REPO:?}" switch -q -c raced-branch
        ;;
      commit)
        git -C "${SAFE_PUSH_TEST_REPO:?}" commit --allow-empty -qm 'raced commit'
        ;;
      upstream)
        git -C "${SAFE_PUSH_TEST_REPO:?}" branch --set-upstream-to=origin/other main >/dev/null
        ;;
      destination)
        git --git-dir="${SAFE_PUSH_TEST_REMOTE:?}" update-ref \
          refs/heads/main "${SAFE_PUSH_TEST_DESTINATION_OID:?}"
        ;;
      worktree)
        mv "${SAFE_PUSH_TEST_REPO:?}/.git" "${SAFE_PUSH_TEST_REPO:?}/.git.safe-push-original"
        printf 'gitdir: %s\n' "${SAFE_PUSH_TEST_OTHER_GIT_DIR:?}" \
          >"${SAFE_PUSH_TEST_REPO:?}/.git"
        ;;
      *) return 2 ;;
    esac
    printf 'raced\n' >"${SAFE_PUSH_TEST_STATE:?}"
  elif [[ "$tool" == gitleaks && -n "${SAFE_PUSH_TEST_RACE:-}" \
          && ! -s "${SAFE_PUSH_TEST_STATE:?}" ]]; then
    printf 'raced\n' >"${SAFE_PUSH_TEST_STATE:?}"
  fi

  if [[ "$tool" == gitleaks && -n "${SAFE_PUSH_TEST_GITLEAKS_SLEEP:-}" ]]; then
    sleep "$SAFE_PUSH_TEST_GITLEAKS_SLEEP"
  fi

  local raced=0
  [ -s "${SAFE_PUSH_TEST_STATE:?}" ] && raced=1

  case "$tool:$1" in
    git:rev-parse)
      case "${2:-}" in
        --show-toplevel)
          if [ "${SAFE_PUSH_TEST_RACE:-}" = worktree ] && [ "$raced" -eq 1 ]; then
            printf '%s\n' /other/worktree
          else
            printf '%s\n' "${SAFE_PUSH_TEST_REPO:?}"
          fi
          ;;
        --absolute-git-dir)
          if [ "${SAFE_PUSH_TEST_RACE:-}" = worktree ] && [ "$raced" -eq 1 ]; then
            printf '%s\n' /other/worktree/.git
          else
            printf '%s/.git\n' "${SAFE_PUSH_TEST_REPO:?}"
          fi
          ;;
        --symbolic-full-name)
          [ "${3:-}" = '@{upstream}' ] || return 2
          if [ "${SAFE_PUSH_TEST_RACE:-}" = upstream ] && [ "$raced" -eq 1 ]; then
            printf '%s\n' refs/remotes/origin/other
          else
            printf '%s\n' refs/remotes/origin/main
          fi
          ;;
        --verify)
          case "${3:-}" in
            "refs/heads/${SAFE_PUSH_TEST_BRANCH:-main}^{commit}")
              if [ "${SAFE_PUSH_TEST_RACE:-}" = commit ] && [ "$raced" -eq 1 ]; then
                printf '%s\n' badc0de
              else
                printf '%s\n' deadbeef
              fi
              ;;
            'refs/remotes/origin/main^{commit}'|'refs/remotes/origin/other^{commit}')
              printf '%s\n' feedface
              ;;
            *) return 2 ;;
          esac
          ;;
        -q)
          [ "${3:-}" = --verify ] || return 2
          case "${4:-}" in
            refs/tags/release-a) printf '%s\n' tagobject ;;
            refs/safe-push-origin/*'^{commit}')
              printf '%s\n' 1111111111111111111111111111111111111111
              ;;
            *) return 1 ;;
          esac
          ;;
        *) return 2 ;;
      esac
      ;;
    git:symbolic-ref)
      [ "${2:-}" = --quiet ] || return 2
      case "${3:-}" in
        HEAD)
          if [ "${SAFE_PUSH_TEST_RACE:-}" = branch ] && [ "$raced" -eq 1 ]; then
            printf '%s\n' refs/heads/switched
          else
            printf 'refs/heads/%s\n' "${SAFE_PUSH_TEST_BRANCH:-main}"
          fi
          ;;
        refs/remotes/origin/HEAD)
          printf '%s\n' refs/remotes/origin/main
          ;;
        *) return 2 ;;
      esac
      ;;
    git:remote)
      [ "${2:-}" = get-url ] && [ "${3:-}" = --push ] && [ "${4:-}" = origin ] || return 2
      printf '%s\n' git@example.test:owner/repo.git
      ;;
    git:check-ref-format) ;;
    git:ls-remote)
      if [ "${2:-}" = --refs ] && [ "${3:-}" = git@example.test:owner/repo.git ]; then
        printf '%s\t%s\n' 1111111111111111111111111111111111111111 refs/heads/main
        return 0
      fi
      [ "${2:-}" = --symref ] && [ "${3:-}" = git@example.test:owner/repo.git ] || return 2
      case "${SAFE_PUSH_TEST_DESTINATION_SHAPE:-normal}" in
        absent) ;;
        ambiguous)
          printf '%s\t%s\n' 1111111111111111111111111111111111111111 "${4:?}"
          printf '%s\t%s\n' 2222222222222222222222222222222222222222 "${4:?}"
          ;;
        malformed) printf 'not-an-oid\t%s\n' "${4:?}" ;;
        symbolic)
          printf 'ref: refs/heads/main\t%s\n' "${4:?}"
          printf '%s\t%s\n' 1111111111111111111111111111111111111111 "${4:?}"
          ;;
        normal)
          if [ "${SAFE_PUSH_TEST_RACE:-}" = destination ] && [ "$raced" -eq 1 ]; then
            printf '%s\t%s\n' 2222222222222222222222222222222222222222 "${4:?}"
          else
            printf '%s\t%s\n' 1111111111111111111111111111111111111111 "${4:?}"
          fi
          ;;
        *) return 2 ;;
      esac
      ;;
    git:merge-base)
      [ "${2:-}" = --is-ancestor ] || return 2
      ;;
    git:rev-list)
      if [ "${2:-}" = -n1 ]; then
        printf '%s\n' deadbeef
      elif [ "${2:-}" = --count ]; then
        printf '%s\n' 1
      else
        printf '%s\n' deadbeef
      fi
      ;;
    git:branch) printf '%s\n' '  origin/main' ;;
    git:for-each-ref)
      case "${2:-}" in
        '--format=%(objectname) %(refname)')
          printf '%s %sheads/main\n' \
            1111111111111111111111111111111111111111 "${3:?}"
          ;;
        '--format=%(refname)') printf '%sheads/main\n' "${3:?}" ;;
        *) return 2 ;;
      esac
      ;;
    git:cat-file)
      case "${2:-}" in
        -e) ;;
        -t)
          [ "${3:-}" = tagobject ] || return 2
          printf '%s\n' tag
          ;;
        -p)
          [ "${3:-}" = tagobject ] || return 2
          printf '%s\n' 'release annotation'
          ;;
        *) return 2 ;;
      esac
      ;;
    git:push|git:fetch|git:update-ref) ;;
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
trap 'rm -rf "${scratch:?}"' EXIT
mkdir -p "$scratch/bin" "$scratch/repo"
trace="$scratch/trace"
state="$scratch/state"
: >"$trace"
: >"$state"
ln -s "$(readlink -f "${BASH_SOURCE[0]}")" "$scratch/bin/git"
ln -s "$(readlink -f "${BASH_SOURCE[0]}")" "$scratch/bin/gitleaks"

case_output=''
case_status=0
case_race=''
case_destination_shape='normal'
case_branch='main'

run_case() {
  : >"$trace"
  : >"$state"
  set +e
  case_output="$(
    cd "$scratch/repo"
    SAFE_PUSH_TEST_SHIM=1 \
      SAFE_PUSH_TEST_TRACE="$trace" \
      SAFE_PUSH_TEST_REPO="$scratch/repo" \
      SAFE_PUSH_TEST_STATE="$state" \
      SAFE_PUSH_TEST_RACE="$case_race" \
      SAFE_PUSH_TEST_DESTINATION_SHAPE="$case_destination_shape" \
      SAFE_PUSH_TEST_BRANCH="$case_branch" \
      XDG_STATE_HOME="$scratch/xdg-state" \
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

run_case --keep-lane
expect_status nonzero
expect_output '--keep-lane needs --to'
expect_no_tool_calls

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

run_case --to
expect_status nonzero
expect_output '--to needs a branch name'
expect_no_tool_calls

run_case --to main --to other
expect_status nonzero
expect_output 'duplicate --to'
expect_no_tool_calls

run_case --to main --tag release-a
expect_status nonzero
expect_output '--to cannot be combined with --tag'
expect_no_tool_calls

for invalid_destination in HEAD refs/heads/main origin/main ../main 'bad name' 'bad..name'; do
  run_case --to "$invalid_destination"
  expect_status nonzero
  expect_output 'invalid destination branch'
  expect_no_tool_calls
done

run_case --help --dry-run
expect_status nonzero
expect_output '--help cannot be combined'
expect_no_tool_calls

run_case --dry-run
expect_status zero
expect_output 'would push main -> origin'
expect_no_mutation
grep -Fq 'gitleaks <detect>' "$trace" || fail 'dry-run skipped the secret scan'

run_case
expect_status zero
expect_output 'pushing main -> origin'
grep -Fq 'gitleaks <detect> <--no-banner> <--redact> <--log-opts=1111111111111111111111111111111111111111..deadbeef>' "$trace" \
  || fail 'branch scan did not use the captured immutable destination..HEAD range'
grep -Fq 'git <push> <--force-with-lease=refs/heads/main:1111111111111111111111111111111111111111> <git@example.test:owner/repo.git> <deadbeef:refs/heads/main>' "$trace" \
  || fail 'branch publication did not use the captured object refspec'

run_case --dry-run --to other
expect_status zero
expect_output 'would push main -> origin as deadbeef:refs/heads/other'
expect_no_mutation

run_case --to other
expect_status zero
expect_output 'pushing main -> origin as deadbeef:refs/heads/other'
grep -Fq 'git <push> <--force-with-lease=refs/heads/other:1111111111111111111111111111111111111111> <git@example.test:owner/repo.git> <deadbeef:refs/heads/other>' "$trace" \
  || fail '--to publication did not use the exact captured destination lease/refspec'

# One-branch-main doctrine: a non-main branch with no explicit --to/--tag is
# refused before any git/gitleaks call — the silent same-name default is exactly
# how feature-branch litter accumulated on origin.
case_branch='feature'
run_case
expect_status nonzero
expect_output 'non-main branch feature: publish with safe-push --to main'
expect_output 'pushing branch names to origin is disabled'
if grep -Fq 'gitleaks' "$trace"; then fail 'non-main refusal reached the secret scan'; fi
if grep -Fq '<push>' "$trace"; then fail 'non-main refusal reached a push'; fi

run_case --dry-run
expect_status nonzero
expect_output 'non-main branch feature: publish with safe-push --to main'
if grep -Fq 'gitleaks' "$trace"; then fail 'non-main refusal reached the secret scan'; fi

# The escape hatch: explicit --to main from a non-main branch proceeds normally.
run_case --to main
expect_status zero
expect_output 'pushing feature -> origin as deadbeef:refs/heads/main'
case_branch='main'

for destination_shape in symbolic ambiguous malformed; do
  case_destination_shape="$destination_shape"
  run_case --to other
  expect_status nonzero
  expect_output 'refusing'
  expect_no_push
done
case_destination_shape='normal'

for race in branch commit destination worktree; do
  case_race="$race"
  run_case
  expect_status nonzero
  expect_output 'repository state changed during secret scan'
  expect_no_push
done
case_race=''

for tag_args in '--dry-run --tag release-a' '--tag release-a --dry-run'; do
  read -r -a parsed_args <<<"$tag_args"
  run_case "${parsed_args[@]}"
  expect_status zero
  expect_output 'would push tag release-a -> origin'
  expect_no_push
  grep -Fq 'gitleaks <detect> <--no-banner> <--redact> <--log-opts=deadbeef ^1111111111111111111111111111111111111111>' "$trace" \
    || fail 'tag dry-run skipped commit history absent from origin'
  grep -Fq 'gitleaks <dir>' "$trace" || fail 'tag dry-run skipped the annotation scan'
done

run_case --tag release-a
expect_status zero
expect_output 'pushing tag release-a -> origin'
grep -Fq 'git <cat-file> <-p> <tagobject>' "$trace" \
  || fail 'tag annotation scan did not read the captured tag object'
grep -Fq 'git <push> <git@example.test:owner/repo.git> <tagobject:refs/tags/release-a>' "$trace" \
  || fail 'tag publication did not use the captured object refspec'

real_git="$(command -v git)"
real_bin="$scratch/real-bin"
mkdir -p "$real_bin"
ln -s "$(readlink -f "${BASH_SOURCE[0]}")" "$real_bin/gitleaks"

make_real_fixture() {
  local label="$1"
  real_fixture="$scratch/real-$label"
  real_repo="$real_fixture/repo"
  real_remote="$real_fixture/remote.git"
  real_other="$real_fixture/other"
  real_trace="$real_fixture/trace"
  real_state="$real_fixture/state"
  mkdir -p "$real_fixture"
  : >"$real_trace"
  : >"$real_state"

  "$real_git" init --bare -q "$real_remote"
  "$real_git" init -q -b main "$real_repo"
  "$real_git" -C "$real_repo" config user.name safe-push-test
  "$real_git" -C "$real_repo" config user.email safe-push-test@example.invalid
  printf 'initial\n' >"$real_repo/content.txt"
  "$real_git" -C "$real_repo" add content.txt
  "$real_git" -C "$real_repo" commit -qm initial
  real_base_oid="$("$real_git" -C "$real_repo" rev-parse HEAD)"
  "$real_git" -C "$real_repo" remote add origin "$real_remote"
  "$real_git" -C "$real_repo" push -q -u origin main
  "$real_git" -C "$real_repo" push -q origin HEAD:refs/heads/other
  "$real_git" -C "$real_repo" commit --allow-empty -qm outgoing

  "$real_git" init -q -b main "$real_other"
  "$real_git" -C "$real_other" config user.name safe-push-test
  "$real_git" -C "$real_other" config user.email safe-push-test@example.invalid
  "$real_git" -C "$real_other" commit --allow-empty -qm other
  "$real_git" -C "$real_other" remote add origin "$real_remote"
  "$real_git" -C "$real_other" push -q origin HEAD:refs/heads/race-target
  real_destination_oid="$("$real_git" -C "$real_other" rev-parse HEAD)"
}

real_remote_state() {
  "$real_git" --git-dir="$real_remote" for-each-ref \
    --format='%(refname) %(objectname)' | sort
}

run_real_case() {
  local race="$1"
  shift
  : >"$real_trace"
  : >"$real_state"
  set +e
  case_output="$(
    cd "$real_repo"
    SAFE_PUSH_TEST_SHIM=1 \
      SAFE_PUSH_TEST_TRACE="$real_trace" \
      SAFE_PUSH_TEST_STATE="$real_state" \
      SAFE_PUSH_TEST_REPO="$real_repo" \
      SAFE_PUSH_TEST_REMOTE="$real_remote" \
      SAFE_PUSH_TEST_DESTINATION_OID="$real_destination_oid" \
      SAFE_PUSH_TEST_REAL_RACE="$race" \
      SAFE_PUSH_TEST_OTHER_GIT_DIR="$real_other/.git" \
      XDG_STATE_HOME="$scratch/xdg-state" \
      PATH="$real_bin:$PATH" \
      "$TARGET" "$@" 2>&1
  )"
  case_status=$?
  set -e

  # The worktree-race fixture deliberately swaps the gitfile while safe-push is
  # between scan and publication. Restore only the isolated scratch repository.
  if [ -d "$real_repo/.git.safe-push-original" ]; then
    [ ! -e "$real_repo/.git" ] || rm -f "${real_repo:?}/.git"
    mv "$real_repo/.git.safe-push-original" "$real_repo/.git"
  fi
}

# Real commit + annotated-tag publication proves captured object refspecs still
# perform the normal operation against an actual bare remote.
make_real_fixture normal
run_real_case ''
expect_status zero
expect_output 'pushing main -> origin'
[ "$("$real_git" -C "$real_repo" rev-parse main)" \
  = "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)" ] \
  || fail 'normal branch publication did not update the remote to captured HEAD'

"$real_git" -C "$real_repo" tag -a release-real -m 'release annotation'
run_real_case '' --tag release-real
expect_status zero
expect_output 'pushing tag release-real -> origin'
[ "$("$real_git" -C "$real_repo" rev-parse refs/tags/release-real)" \
  = "$("$real_git" --git-dir="$real_remote" rev-parse refs/tags/release-real)" ] \
  || fail 'normal tag publication did not update the remote to the captured tag object'

# A support-only commit may be published by tag without adding a remote branch;
# its commit history and annotation must both pass the secret scan first.
make_real_fixture support-tag
"$real_git" -C "$real_repo" tag -a release-support -m 'support release annotation'
remote_main_before="$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)"
run_real_case '' --tag release-support
expect_status zero
expect_output 'pushing tag release-support -> origin'
grep -Fq 'gitleaks <detect> <--no-banner> <--redact> <--log-opts=' "$real_trace" \
  || fail 'support-only tag skipped its commit-history scan'
grep -Fq 'gitleaks <dir>' "$real_trace" \
  || fail 'support-only tag skipped its annotation scan'
[ "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)" = "$remote_main_before" ] \
  || fail 'support-only tag publication changed remote main'
if "$real_git" --git-dir="$real_remote" rev-parse --verify refs/heads/support-tag >/dev/null 2>&1; then
  fail 'support-only tag publication created a remote support branch'
fi
[ "$("$real_git" -C "$real_repo" rev-parse refs/tags/release-support)" \
  = "$("$real_git" --git-dir="$real_remote" rev-parse refs/tags/release-support)" ] \
  || fail 'support-only tag publication did not publish the captured tag object'

# A new branch with no upstream is off the default branch, so the one-branch-main
# guard refuses the bare default before any scan or push — no same-name litter,
# no tracking established.
make_real_fixture no-upstream
"$real_git" -C "$real_repo" switch -q -c topic
"$real_git" -C "$real_repo" commit --allow-empty -qm topic
remote_before="$(real_remote_state)"
run_real_case ''
expect_status nonzero
expect_output 'non-main branch topic'
[ "$(real_remote_state)" = "$remote_before" ] \
  || fail 'non-main refusal mutated the remote'
if "$real_git" -C "$real_repo" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
  fail 'non-main refusal established local tracking'
fi

# A feature branch can inherit origin/main when it is created from that remote
# ref. The guard refuses the bare default regardless of inherited tracking —
# it never reaches the code that would decide which remote ref to touch.
make_real_fixture inherited-upstream
remote_main_before="$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)"
"$real_git" -C "$real_repo" switch -q -c feature
"$real_git" -C "$real_repo" commit --allow-empty -qm feature
"$real_git" -C "$real_repo" branch --set-upstream-to=origin/main feature >/dev/null
run_real_case ''
expect_status nonzero
expect_output 'non-main branch feature'
[ "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)" = "$remote_main_before" ] \
  || fail 'inherited origin/main upstream let the refused default push touch remote main'
if "$real_git" --git-dir="$real_remote" rev-parse --verify refs/heads/feature >/dev/null 2>&1; then
  fail 'non-main refusal advanced a remote feature ref'
fi

# Dry-run is not an escape hatch: a non-main branch with no --to is refused even
# under --dry-run, leaving the remote and local tracking configuration untouched.
make_real_fixture dry-run-destination
"$real_git" -C "$real_repo" switch -q -c feature
"$real_git" -C "$real_repo" commit --allow-empty -qm feature
remote_before="$(real_remote_state)"
run_real_case '' --dry-run
expect_status nonzero
expect_output 'non-main branch feature'
[ "$(real_remote_state)" = "$remote_before" ] \
  || fail 'dry-run mutated the remote'
if "$real_git" -C "$real_repo" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
  fail 'dry-run established local tracking'
fi

# Cross-branch publication is available only through --to and scans the exact
# remote-destination..HEAD range before an object+lease-bound update.
make_real_fixture explicit-main
remote_main_before="$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)"
"$real_git" -C "$real_repo" switch -q -c feature
"$real_git" -C "$real_repo" commit --allow-empty -qm feature
feature_oid="$("$real_git" -C "$real_repo" rev-parse feature)"
run_real_case '' --to main
expect_status zero
expect_output "pushing feature -> origin as $feature_oid:refs/heads/main"
grep -Fq "<--log-opts=$remote_main_before..$feature_oid>" "$real_trace" \
  || fail '--to did not scan the exact destination..HEAD range'
[ "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)" = "$feature_oid" ] \
  || fail '--to main did not advance the explicit destination'
if "$real_git" -C "$real_repo" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
  fail '--to unexpectedly changed local branch tracking'
fi

# A new destination branch scans only what origin's default branch lacks, not
# the whole reachable history.
make_real_fixture new-destination
remote_main_before="$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)"
"$real_git" -C "$real_repo" switch -q -c scratch
"$real_git" -C "$real_repo" commit --allow-empty -qm scratch
scratch_oid="$("$real_git" -C "$real_repo" rev-parse scratch)"
run_real_case '' --to farm/scan-test
expect_status zero
grep -Fq "<--log-opts=$remote_main_before..$scratch_oid>" "$real_trace" \
  || fail 'new destination branch did not scan only commits missing from origin main'
[ "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/farm/scan-test)" = "$scratch_oid" ] \
  || fail 'new destination branch was not created at HEAD'

# Destination ancestry is checked before scanning or pushing. An unrelated
# remote main is rejected even when --to makes the target explicit.
make_real_fixture non-fast-forward
"$real_git" -C "$real_repo" fetch -q origin race-target:refs/remotes/origin/race-target
"$real_git" --git-dir="$real_remote" update-ref refs/heads/main "$real_destination_oid"
"$real_git" -C "$real_repo" switch -q -c feature "$real_base_oid"
"$real_git" -C "$real_repo" commit --allow-empty -qm feature
remote_before="$(real_remote_state)"
run_real_case '' --to main
expect_status nonzero
expect_output 'non-fast-forward'
[ "$(real_remote_state)" = "$remote_before" ] \
  || fail 'non-fast-forward refusal mutated the remote'
[ ! -s "$real_trace" ] || fail 'non-fast-forward refusal reached gitleaks'

# A branch ref that resolves symbolically on the remote is not a concrete
# destination and must be rejected before publication.
make_real_fixture symbolic-destination
"$real_git" --git-dir="$real_remote" symbolic-ref refs/heads/alias refs/heads/main
remote_before="$(real_remote_state)"
run_real_case '' --to alias
expect_status nonzero
expect_output 'is symbolic'
[ "$(real_remote_state)" = "$remote_before" ] \
  || fail 'symbolic destination refusal mutated the remote'

# Each race is planted by the gitleaks process after the scan begins. The exact
# real remote ref set must remain unchanged; a mocked "push was not called" is
# not sufficient evidence for this security boundary.
for race in branch commit destination worktree; do
  make_real_fixture "race-$race"
  remote_before="$(real_remote_state)"
  run_real_case "$race"
  expect_status nonzero
  expect_output 'repository state changed during secret scan'
  remote_after="$(real_remote_state)"
  if [ "$race" = destination ]; then
    [ "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)" = "$real_destination_oid" ] \
      || fail 'destination race was not preserved as the sole remote mutation'
    [[ "$case_output" != *'pushing main -> origin'* ]] \
      || fail 'safe-push published after the destination changed during its scan'
  else
    [ "$remote_after" = "$remote_before" ] \
      || fail "$race race mutated the remote despite fail-closed verdict"
  fi
done

make_landing_clone() {
  local dir="$1" file="$2"
  "$real_git" clone -q "$landing_remote" "$dir"
  "$real_git" -C "$dir" config user.name safe-push-test
  "$real_git" -C "$dir" config user.email safe-push-test@example.invalid
  "$real_git" -C "$dir" switch -q -c "lane-${dir##*/}"
  printf '%s\n' "${dir##*/}" >"$dir/$file"
  "$real_git" -C "$dir" add "$file"
  "$real_git" -C "$dir" commit -qm "change from ${dir##*/}"
}

run_landing() {
  local dir="$1"
  (
    cd "$dir"
    SAFE_PUSH_TEST_SHIM=1 \
      SAFE_PUSH_TEST_TRACE="$dir.trace" \
      SAFE_PUSH_TEST_STATE="$dir.state" \
      SAFE_PUSH_TEST_GITLEAKS_SLEEP="${landing_sleep:-}" \
      XDG_STATE_HOME="$scratch/xdg-state" \
      PATH="$real_bin:$PATH" \
      "$TARGET" --to main
  ) >"$dir.out" 2>&1
}

new_landing_origin() {
  landing_root="$scratch/landing-$1"
  landing_remote="$landing_root/remote.git"
  mkdir -p "$landing_root"
  "$real_git" init --bare -q -b main "$landing_remote"
  "$real_git" init -q -b main "$landing_root/seed"
  "$real_git" -C "$landing_root/seed" config user.name safe-push-test
  "$real_git" -C "$landing_root/seed" config user.email safe-push-test@example.invalid
  printf 'base\n' >"$landing_root/seed/shared.txt"
  "$real_git" -C "$landing_root/seed" add shared.txt
  "$real_git" -C "$landing_root/seed" commit -qm base
  "$real_git" -C "$landing_root/seed" push -q "$landing_remote" main
}

# Concurrent landings from lanes cut at the same base serialize on the
# per-origin lock; the later one rebases onto the earlier, so both land in
# order with no non-fast-forward rejection.
new_landing_origin concurrent
make_landing_clone "$landing_root/a" a.txt
make_landing_clone "$landing_root/b" b.txt
landing_sleep=2
run_landing "$landing_root/a" & pid_a=$!
run_landing "$landing_root/b" & pid_b=$!
status_a=0; wait "$pid_a" || status_a=$?
status_b=0; wait "$pid_b" || status_b=$?
landing_sleep=''
case_output="$(cat "$landing_root/a.out" "$landing_root/b.out")"
case_status=$((status_a + status_b))
[ "$case_status" -eq 0 ] || fail 'concurrent landing: a run failed'
expect_output 'waiting for the landing lock'
expect_output 'rebasing onto it'
if grep -Eq 'non-fast-forward|rejected|state changed' <<<"$case_output"; then
  fail 'concurrent landing hit a non-fast-forward or race refusal'
fi
[ "$("$real_git" --git-dir="$landing_remote" rev-list --count main)" -eq 3 ] \
  || fail 'concurrent landing: origin main does not carry base plus both changes'
[ "$("$real_git" --git-dir="$landing_remote" rev-list --merges --count main)" -eq 0 ] \
  || fail 'concurrent landing: history is not linear'
for f in a.txt b.txt shared.txt; do
  "$real_git" --git-dir="$landing_remote" cat-file -e "main:$f" \
    || fail "concurrent landing: origin main lacks $f"
done

# A lane whose change conflicts with what landed meanwhile is refused with
# the file named, and the rebase is aborted so the worktree is left clean.
new_landing_origin conflict
make_landing_clone "$landing_root/lane" shared.txt
lane_head="$("$real_git" -C "$landing_root/lane" rev-parse HEAD)"
printf 'landed first\n' >"$landing_root/seed/shared.txt"
"$real_git" -C "$landing_root/seed" commit -qam 'conflicting landing'
"$real_git" -C "$landing_root/seed" push -q "$landing_remote" main
remote_main_before="$("$real_git" --git-dir="$landing_remote" rev-parse main)"
case_status=0
run_landing "$landing_root/lane" || case_status=$?
case_output="$(cat "$landing_root/lane.out")"
expect_status nonzero
expect_output 'conflicts in:'
expect_output 'shared.txt'
[ -z "$("$real_git" -C "$landing_root/lane" status --porcelain)" ] \
  || fail 'conflict refusal left the worktree dirty'
for d in rebase-merge rebase-apply; do
  [ ! -e "$("$real_git" -C "$landing_root/lane" rev-parse --absolute-git-dir)/$d" ] \
    || fail 'conflict refusal left a rebase in progress'
done
[ "$("$real_git" -C "$landing_root/lane" rev-parse HEAD)" = "$lane_head" ] \
  || fail 'conflict refusal moved the lane HEAD'
[ "$("$real_git" --git-dir="$landing_remote" rev-parse main)" = "$remote_main_before" ] \
  || fail 'conflict refusal mutated origin main'

# Lane cleanup: a landed lane under <container>/worktrees/<slug> is removed
# with its branch, judged against origin main even while the main checkout's
# local main is stale.
new_lane_container() {
  lane_container="$scratch/lanes-$1"
  lane_remote="$lane_container/remote.git"
  lane="$lane_container/worktrees/lane"
  mkdir -p "$lane_container/worktrees"
  "$real_git" init --bare -q -b main "$lane_remote"
  "$real_git" init -q -b main "$lane_container/main"
  "$real_git" -C "$lane_container/main" config user.name safe-push-test
  "$real_git" -C "$lane_container/main" config user.email safe-push-test@example.invalid
  "$real_git" -C "$lane_container/main" commit --allow-empty -qm base
  "$real_git" -C "$lane_container/main" remote add origin "$lane_remote"
  "$real_git" -C "$lane_container/main" push -q -u origin main
  "$real_git" -C "$lane_container/main" worktree add -q "$lane" -b lane
  "$real_git" -C "$lane" commit --allow-empty -qm lane-work
}

run_lane() {
  set +e
  case_output="$(
    cd "$lane"
    SAFE_PUSH_TEST_SHIM=1 \
      SAFE_PUSH_TEST_TRACE="$lane_container/trace" \
      SAFE_PUSH_TEST_STATE="$lane_container/state" \
      XDG_STATE_HOME="$scratch/xdg-state" \
      PATH="$real_bin:$PATH" \
      "$TARGET" --to main "$@" 2>&1
  )"
  case_status=$?
  set -e
}

lane_branch_exists() {
  "$real_git" -C "$lane_container/main" rev-parse -q --verify refs/heads/lane >/dev/null
}

remote_lane_exists() {
  "$real_git" --git-dir="$lane_remote" rev-parse -q --verify refs/heads/lane >/dev/null
}

new_lane_container clean
run_lane
expect_status zero
expect_output 'no longer exists'
[ ! -e "$lane" ] || fail 'landed clean lane was not removed'
! lane_branch_exists || fail 'landed clean lane branch was not deleted'

new_lane_container keep
run_lane --keep-lane
expect_status zero
expect_output '--keep-lane: keeping'
[ -d "$lane" ] || fail '--keep-lane removed the lane'
lane_branch_exists || fail '--keep-lane deleted the lane branch'

new_lane_container dirty
printf 'unsaved\n' >"$lane/notes.txt"
run_lane
expect_status zero
expect_output 'uncommitted or untracked files, so it was kept'
[ -f "$lane/notes.txt" ] || fail 'dirty lane was removed'
lane_branch_exists || fail 'dirty lane branch was deleted'

new_lane_container remote-merged
"$real_git" -C "$lane" push -q origin lane
run_lane
expect_status zero
expect_output 'origin lane is fully on main'
! remote_lane_exists || fail 'merged remote lane branch was not deleted'
[ ! -e "$lane" ] || fail 'landed lane with a merged remote branch was not removed'

new_lane_container remote-unmerged
"$real_git" -C "$lane" commit --allow-empty -qm 'only on the remote branch'
"$real_git" -C "$lane" push -q origin lane
"$real_git" -C "$lane" reset -q --hard HEAD~1
run_lane
expect_status zero
remote_lane_exists || fail 'remote lane branch with unlanded work was deleted'

printf 'safe-push tests: PASS\n'
