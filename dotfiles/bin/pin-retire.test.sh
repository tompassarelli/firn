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
