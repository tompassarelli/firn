#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
target="$repo/dotfiles/bin/pin-retire"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pin-retire-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT
test_home="$scratch/home"
container="$test_home/code/proj"
main="$container/main"
mkdir -p "$container/pins"
git init -q -b main "$main"
git -C "$main" config user.name pin-retire-test
git -C "$main" config user.email pin-retire-test@example.invalid
project_remote="$test_home/remotes/proj.git"
mkdir -p "$(dirname "$project_remote")"
git init -q --bare "$project_remote"
git -C "$main" remote add origin "$project_remote"

pass=0
fail_count=0
ok() { pass=$((pass + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; fail_count=$((fail_count + 1)); }

new_pin() {
  local label="$1" oid pin
  printf '%s\n' "$label" >>"$main/history.txt"
  git -C "$main" add history.txt
  git -C "$main" commit -qm "$label"
  oid="$(git -C "$main" rev-parse HEAD)"
  pin="$container/pins/$oid"
  git -C "$main" worktree add -q --detach "$pin" "$oid"
  printf 'consumer-main: %s\nConsumer: fixture %s.\n' "$consumer" "$label" >"$pin.pin"
  printf '%s\n' "$pin"
}

consumer="$test_home/code/consumer/main"
consumer_remote="$test_home/remotes/consumer.git"
mkdir -p "$(dirname "$consumer")"
mkdir -p "$(dirname "$consumer_remote")"
git init -q --bare "$consumer_remote"
git init -q -b main "$consumer"
git -C "$consumer" config user.name pin-retire-test
git -C "$consumer" config user.email pin-retire-test@example.invalid
printf 'current\n' >"$consumer/pin.ref"
git -C "$consumer" add pin.ref
git -C "$consumer" commit -qm current
git -C "$consumer" remote add origin "$consumer_remote"
git -C "$consumer" push -qu origin main

same_repo_pin="$(new_pin same-repository-consumer)"
git -C "$main" push -qu origin main
printf 'consumer-main: %s\nConsumer: same repository fixture.\n' \
  "$main" >"$same_repo_pin.pin"
if HOME="$test_home" "$target" --dry-run --consumer-main "$main" -- \
    "$same_repo_pin" | grep -Fq 'DRY RUN'; then
  ok
else
  fail 'same-repository pin treated its own administrative pointer as a consumer'
fi

same_repo_lane="$container/worktrees/other"
mkdir -p "$(dirname "$same_repo_lane")"
git -C "$main" worktree add -q -b same-repository-reference \
  "$same_repo_lane" main
printf 'pin %s\n' "$same_repo_pin" >"$same_repo_lane/pin.ref"
git -C "$same_repo_lane" add pin.ref
git -C "$same_repo_lane" commit -qm 'other lane uses same-repository pin'
if HOME="$test_home" "$target" --dry-run --consumer-main "$main" -- \
    "$same_repo_pin" 2>"$scratch/same-repo-lane-error"; then
  fail 'different same-repository worktree reference was accepted'
elif grep -Fq "consumer worktree still references the pin: $same_repo_lane" \
    "$scratch/same-repo-lane-error"; then
  ok
else
  fail 'same-repository worktree refusal did not name the different lane'
fi
git -C "$main" worktree remove "$same_repo_lane"
if HOME="$test_home" "$target" --consumer-main "$main" -- \
    "$same_repo_pin" >/dev/null; then
  ok
else
  fail 'same-repository retirement failed after the other reference moved'
fi
[ ! -e "$same_repo_pin" ] && [ ! -e "$same_repo_pin.pin" ] \
  || fail 'same-repository retirement left pin or sidecar'

pin1="$(new_pin valid)"
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$pin1" >/dev/null; then ok; else fail 'valid retirement failed'; fi
[ ! -e "$pin1" ] && [ ! -e "$pin1.pin" ] || fail 'valid retirement left pin or sidecar'
git -C "$main" worktree list --porcelain | grep -Fq "$pin1" \
  && fail 'valid retirement remained registered' || ok

pin2="$(new_pin proof-required)"
if HOME="$test_home" "$target" -- "$pin2" >/dev/null 2>&1; then fail 'missing consumer proof was accepted'; else ok; fi
[ -d "$pin2" ] && [ -f "$pin2.pin" ] || fail 'missing consumer proof mutated the pin'

other_consumer="$test_home/code/other/main"
mkdir -p "$(dirname "$other_consumer")"
git clone -qb main "$consumer_remote" "$other_consumer"
git -C "$other_consumer" checkout -q --detach
if HOME="$test_home" "$target" --consumer-main "$other_consumer" -- "$pin2" >/dev/null 2>&1; then fail 'detached consumer checkout was accepted'; else ok; fi
[ -d "$pin2" ] && [ -f "$pin2.pin" ] || fail 'detached-consumer refusal mutated the pin'
git -C "$other_consumer" switch -q main
if HOME="$test_home" "$target" --consumer-main "$other_consumer" -- "$pin2" >/dev/null 2>&1; then fail 'consumer arguments differing from the sidecar were accepted'; else ok; fi
[ -d "$pin2" ] && [ -f "$pin2.pin" ] || fail 'consumer-set refusal mutated the pin'

printf 'ahead\n' >"$consumer/ahead.txt"
git -C "$consumer" add ahead.txt
git -C "$consumer" commit -qm ahead
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$pin2" >/dev/null 2>&1; then fail 'unpublished consumer main was accepted'; else ok; fi
[ -d "$pin2" ] && [ -f "$pin2.pin" ] || fail 'unpublished-consumer refusal mutated the pin'
git -C "$consumer" push -qu origin main

lane="$test_home/code/consumer/worktrees/playable"
git -C "$consumer" worktree add -q -b playable "$lane" main
printf 'pin %s\n' "$pin2" >"$lane/pin.ref"
git -C "$lane" add pin.ref
git -C "$lane" commit -qm 'playable lane uses pin'
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$pin2" \
    2>"$scratch/lane-error"; then
  fail 'consumer worktree reference was accepted'
elif grep -Fq "consumer worktree still references the pin: $lane" "$scratch/lane-error"; then
  ok
else
  fail 'consumer worktree refusal did not name the lane'
fi
git -C "$consumer" worktree remove "$lane"

if HOME="$test_home" "$target" --dry-run --consumer-main "$consumer" -- "$pin2" | grep -Fq 'DRY RUN'; then ok; else fail 'dry-run did not report itself'; fi
[ -d "$pin2" ] && [ -f "$pin2.pin" ] || fail 'dry-run mutated the pin'

printf 'untracked\n' >"$pin2/untracked.txt"
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$pin2" >/dev/null 2>&1; then fail 'dirty pin was retired'; else ok; fi
[ -d "$pin2" ] && [ -f "$pin2.pin" ] || fail 'dirty refusal mutated the pin'

pin3="$(new_pin empty-sidecar)"
: >"$pin3.pin"
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$pin3" >/dev/null 2>&1; then fail 'empty sidecar was accepted'; else ok; fi
[ -d "$pin3" ] && [ -f "$pin3.pin" ] || fail 'empty-sidecar refusal mutated the pin'

pin4="$(new_pin wrong-name)"
wrong="$container/pins/0000000000000000000000000000000000000000"
git -C "$main" worktree move "$pin4" "$wrong"
mv "$pin4.pin" "$wrong.pin"
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$wrong" >/dev/null 2>&1; then fail 'path/HEAD mismatch was accepted'; else ok; fi
[ -d "$wrong" ] && [ -f "$wrong.pin" ] || fail 'path/HEAD refusal mutated the pin'

if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$container/pins" >/dev/null 2>&1; then fail 'pins root was accepted'; else ok; fi

pin5="$(new_pin still-consumed)"
printf 'pin %s\n' "$pin5" >"$consumer/pin.ref"
git -C "$consumer" add pin.ref
git -C "$consumer" commit -qm 'reference old pin'
git -C "$consumer" push -qu origin main
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$pin5" >/dev/null 2>&1; then fail 'live consumer reference was accepted'; else ok; fi
[ -d "$pin5" ] && [ -f "$pin5.pin" ] || fail 'consumer-reference refusal mutated the pin'

pin6="$(new_pin legacy-sidecar)"
printf 'Consumer: unstructured fixture.\n' >"$pin6.pin"
if HOME="$test_home" "$target" --consumer-main "$consumer" -- "$pin6" >/dev/null 2>&1; then fail 'unstructured legacy sidecar was accepted'; else ok; fi
[ -d "$pin6" ] && [ -f "$pin6.pin" ] || fail 'legacy-sidecar refusal mutated the pin'

git -C "$main" push -qu origin main
u_ref="$(new_pin unconsumed-referenced)"
rm -- "$u_ref.pin"
git -C "$main" push -qu origin main
printf 'pin %s\n' "$(basename "$u_ref")" >"$consumer/unconsumed.ref"
if HOME="$test_home" "$target" --unconsumed -- "$u_ref" 2>"$scratch/u-ref-error" >/dev/null; then
  fail 'referenced unconsumed pin was retired'
elif grep -Fq "$consumer/unconsumed.ref" "$scratch/u-ref-error"; then ok
else fail 'referenced unconsumed refusal did not name the referencing file'; fi
[ -d "$u_ref" ] || fail 'referenced unconsumed refusal mutated the pin'
rm -- "$consumer/unconsumed.ref"

u_lost_oid="$(git -C "$main" commit-tree -m unreachable "HEAD^{tree}")"
u_lost="$container/pins/$u_lost_oid"
git -C "$main" worktree add -q --detach "$u_lost" "$u_lost_oid"
if HOME="$test_home" "$target" --unconsumed -- "$u_lost" 2>"$scratch/u-lost-error" >/dev/null; then
  fail 'unreachable unconsumed pin was retired'
elif grep -Fq 'is not reachable' "$scratch/u-lost-error"; then ok
else fail 'unreachable unconsumed refusal gave the wrong reason'; fi
[ -d "$u_lost" ] || fail 'unreachable unconsumed refusal mutated the pin'

if HOME="$test_home" "$target" --unconsumed -- "$u_ref" >"$scratch/u-ok-out"; then
  grep -Fq '(b) reachable from: refs/heads/main refs/remotes/origin/main' "$scratch/u-ok-out" \
    && grep -Fq '(c) references: none' "$scratch/u-ok-out" && ok \
    || fail 'unconsumed retirement did not print its proof'
else fail 'unconsumed reachable pin was refused'; fi
[ ! -e "$u_ref" ] || fail 'unconsumed retirement left the pin'

printf 'short\n' >>"$main/history.txt"
git -C "$main" commit -qam short-named
git -C "$main" push -q origin main
u_short_oid="$(git -C "$main" rev-parse HEAD)"
u_short="$container/pins/${u_short_oid:0:12}"
git -C "$main" worktree add -q --detach "$u_short" "$u_short_oid"
printf 'see ~/code/proj/pins/%s\n' "${u_short_oid:0:12}" >"$consumer/short.ref"
if HOME="$test_home" "$target" --unconsumed -- "$u_short" >/dev/null 2>&1; then
  fail 'short-named pin referenced by its pin path was retired'
else ok; fi
printf 'fixed in commit %s\n' "$u_short_oid" >"$consumer/short.ref"
if HOME="$test_home" "$target" --unconsumed -- "$u_short" >/dev/null 2>"$scratch/u-short-error"; then
  ok
else fail "short-named pin whose full commit is cited was refused: $(cat "$scratch/u-short-error")"; fi
[ ! -e "$u_short" ] || fail 'short-named retirement left the pin'
rm -- "$consumer/short.ref"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$target" && ok || fail 'shellcheck rejected pin-retire'
else
  ok
fi

if [ "$fail_count" -eq 0 ]; then
  printf 'pin-retire tests: PASS (%d checks)\n' "$pass"
else
  printf 'pin-retire tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
