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
            'refs/heads/main^{commit}')
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
            *) return 1 ;;
          esac
          ;;
        *) return 2 ;;
      esac
      ;;
    git:symbolic-ref)
      [ "${2:-}" = --quiet ] && [ "${3:-}" = HEAD ] || return 2
      if [ "${SAFE_PUSH_TEST_RACE:-}" = branch ] && [ "$raced" -eq 1 ]; then
        printf '%s\n' refs/heads/switched
      else
        printf '%s\n' refs/heads/main
      fi
      ;;
    git:remote)
      [ "${2:-}" = get-url ] && [ "${3:-}" = --push ] && [ "${4:-}" = origin ] || return 2
      printf '%s\n' git@example.test:owner/repo.git
      ;;
    git:check-ref-format) ;;
    git:ls-remote)
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
      if [ "${2:-}" = -n1 ]; then printf '%s\n' deadbeef; else printf '%s\n' deadbeef; fi
      ;;
    git:branch) printf '%s\n' '  origin/main' ;;
    git:cat-file)
      case "${2:-}" in
        -e) ;;
        -p)
          [ "${3:-}" = tagobject ] || return 2
          printf '%s\n' 'release annotation'
          ;;
        *) return 2 ;;
      esac
      ;;
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

# A new branch with no upstream scans the captured full history, pushes its
# captured object, then establishes the expected tracking relationship.
make_real_fixture no-upstream
"$real_git" -C "$real_repo" switch -q -c topic
"$real_git" -C "$real_repo" commit --allow-empty -qm topic
topic_oid="$("$real_git" -C "$real_repo" rev-parse topic)"
run_real_case ''
expect_status zero
grep -Fq "<--log-opts=$topic_oid>" "$real_trace" \
  || fail 'no-upstream scan did not use the captured topic history'
[ "$("$real_git" -C "$real_repo" rev-parse topic)" \
  = "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/topic)" ] \
  || fail 'no-upstream publication did not push the captured topic object'
[ "$("$real_git" -C "$real_repo" rev-parse --abbrev-ref '@{upstream}')" = origin/topic ] \
  || fail 'no-upstream publication did not establish origin/topic tracking'

# A feature branch can inherit origin/main when it is created from that remote
# ref. Default safe-push must publish the local branch name, never the inherited
# upstream destination.
make_real_fixture inherited-upstream
remote_main_before="$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)"
"$real_git" -C "$real_repo" switch -q -c feature
"$real_git" -C "$real_repo" commit --allow-empty -qm feature
feature_oid="$("$real_git" -C "$real_repo" rev-parse feature)"
"$real_git" -C "$real_repo" branch --set-upstream-to=origin/main feature >/dev/null
run_real_case ''
expect_status zero
[ "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/main)" = "$remote_main_before" ] \
  || fail 'inherited origin/main upstream redirected the default push to remote main'
[ "$("$real_git" --git-dir="$real_remote" rev-parse refs/heads/feature)" = "$feature_oid" ] \
  || fail 'default push did not advance the same-named remote feature ref'
[ "$("$real_git" -C "$real_repo" rev-parse --abbrev-ref '@{upstream}')" = origin/feature ] \
  || fail 'default push did not repair inherited tracking to origin/feature'

# Dry-run names the immutable source object and exact same-named destination,
# while leaving both the remote and local tracking configuration unchanged.
make_real_fixture dry-run-destination
"$real_git" -C "$real_repo" switch -q -c feature
"$real_git" -C "$real_repo" commit --allow-empty -qm feature
feature_oid="$("$real_git" -C "$real_repo" rev-parse feature)"
remote_before="$(real_remote_state)"
run_real_case '' --dry-run
expect_status zero
expect_output "would push feature -> origin as $feature_oid:refs/heads/feature"
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

printf 'safe-push tests: PASS\n'
