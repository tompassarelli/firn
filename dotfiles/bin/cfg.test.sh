#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/cfg"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/cfg-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

pass=0
fail_count=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

ok() {
  pass=$((pass + 1))
}

check() {
  if [ "$2" = "$3" ]; then ok; else fail "$1: want '$3', got '$2'"; fi
}

RECORD_REL="dotfiles/niri/config.kdl"
LIVE_REL=".config/niri/config.kdl"

# A fresh container ($1/main is a git checkout) + a fresh HOME ($1/home).
# Every case gets its own, so no case can observe another's leftovers.
make_fixture() {
  local root="$1" main="$1/container/main"
  mkdir -p "$main/dotfiles/niri" "$root/home"
  git init -q -b main "$main"
  git -C "$main" config user.name cfg-test
  git -C "$main" config user.email cfg-test@example.invalid
  printf 'settled line one\nsettled line two\n' >"$main/$RECORD_REL"
  git -C "$main" add "$RECORD_REL"
  git -C "$main" commit -qm 'record'
}

run_cfg() {
  local root="$1"; shift
  HOME="$root/home" CFG_REPO="$root/container/main" "$TARGET" "$@"
}

# --- status: in-sync -------------------------------------------------------
f="$scratch/insync"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
cp "$f/container/main/$RECORD_REL" "$f/home/$LIVE_REL"
out="$(run_cfg "$f" status)"
if grep -Eq '^niri +in-sync' <<<"$out"; then ok; else fail "status in-sync, got: $out"; fi

# --- status: drifted, with diffstat ---------------------------------------
f="$scratch/drifted"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
printf 'settled line one\nlive tweak\nanother tweak\n' >"$f/home/$LIVE_REL"
out="$(run_cfg "$f" status)"
if grep -Eq '^niri +drifted' <<<"$out"; then ok; else fail "status drifted, got: $out"; fi
if grep -Fq '+2 -1' <<<"$out"; then ok; else fail "diffstat '+2 -1', got: $out"; fi

# name filter narrows to the one row; an unknown name yields nothing
out="$(run_cfg "$f" status niri)"
check "status niri row count" "$(wc -l <<<"$out")" 1
out="$(run_cfg "$f" status nosuch)"
check "status filter on unknown name" "$out" ""

# diff shows the live-side tweak
out="$(run_cfg "$f" diff niri)"
if grep -Fq '+live tweak' <<<"$out"; then ok; else fail "diff missing '+live tweak', got: $out"; fi

# --- status: a still-symlinked live path reads as wired --------------------
f="$scratch/wired"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
ln -s "$f/container/main/$RECORD_REL" "$f/home/$LIVE_REL"
out="$(run_cfg "$f" status)"
if grep -Eq '^niri +wired' <<<"$out"; then ok; else fail "status wired, got: $out"; fi

# --- reset --yes restores the live file from the record --------------------
f="$scratch/reset"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
printf 'garbage\n' >"$f/home/$LIVE_REL"

if run_cfg "$f" reset niri >/dev/null 2>&1; then
  fail "reset without --yes succeeded"
else
  ok
fi
check "reset without --yes left live alone" "$(cat "$f/home/$LIVE_REL")" "garbage"

run_cfg "$f" reset niri --yes >/dev/null
if cmp -s "$f/container/main/$RECORD_REL" "$f/home/$LIVE_REL"; then
  ok
else
  fail "reset --yes did not restore the live file"
fi
if [ -f "$f/home/$LIVE_REL" ] && [ ! -L "$f/home/$LIVE_REL" ]; then
  ok
else
  fail "reset produced something other than a regular file"
fi

# reset must replace a symlink, never write through it into the checkout
f="$scratch/reset-symlink"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
ln -s "$f/container/main/$RECORD_REL" "$f/home/$LIVE_REL"
run_cfg "$f" reset niri --yes >/dev/null
if [ ! -L "$f/home/$LIVE_REL" ]; then ok; else fail "reset kept the symlink"; fi
check "record untouched by reset-through-symlink" \
  "$(git -C "$f/container/main" status --porcelain)" ""

# --- promote: live -> record, landed on main, worktree cleaned up ----------
f="$scratch/promote"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
printf 'settled line one\nsettled line two\npromoted knob\n' >"$f/home/$LIVE_REL"
before="$(git -C "$f/container/main" rev-parse HEAD)"

out="$(run_cfg "$f" promote niri)"
after="$(git -C "$f/container/main" rev-parse HEAD)"

if [ "$before" != "$after" ]; then ok; else fail "promote did not advance main"; fi
if cmp -s "$f/container/main/$RECORD_REL" "$f/home/$LIVE_REL"; then
  ok
else
  fail "promote did not settle the live content into the record"
fi
check "promote left main clean" "$(git -C "$f/container/main" status --porcelain)" ""
check "promote is a fast-forward of the old head" \
  "$(git -C "$f/container/main" rev-list --count "$before..$after")" 1
if grep -Fq 'promoted niri' <<<"$out"; then ok; else fail "promote output, got: $out"; fi

# no stray worktree or branch survives the promote
check "no leftover promote worktree dir" \
  "$(find "$f/container" -maxdepth 1 -name 'wt-cfg-promote-*' | wc -l)" 0
check "no leftover promote worktree registration" \
  "$(git -C "$f/container/main" worktree list | grep -c 'wt-cfg-promote-' || true)" 0
check "no leftover promote branch" \
  "$(git -C "$f/container/main" branch --list 'cfg-promote-*' | wc -l)" 0

# a second promote with nothing to say is a no-op, not an empty commit
head_after="$(git -C "$f/container/main" rev-parse HEAD)"
out="$(run_cfg "$f" promote niri)"
check "idempotent promote leaves head alone" \
  "$(git -C "$f/container/main" rev-parse HEAD)" "$head_after"
if grep -Fq 'already in sync' <<<"$out"; then ok; else fail "no-op promote output: $out"; fi

# promote refuses a still-symlinked live path rather than promoting the record
f="$scratch/promote-symlink"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
ln -s "$f/container/main/$RECORD_REL" "$f/home/$LIVE_REL"
if run_cfg "$f" promote niri >/dev/null 2>&1; then
  fail "promote accepted a symlinked live path"
else
  ok
fi

# --- materialize: symlink -> regular file holding the RESOLVED content -----
f="$scratch/mat-symlink"; make_fixture "$f"
mkdir -p "$f/home/.config/niri" "$f/target"
printf 'resolved uncommitted content\n' >"$f/target/config.kdl"
ln -s "$f/target/config.kdl" "$f/home/$LIVE_REL"
run_cfg "$f" materialize >/dev/null
if [ ! -L "$f/home/$LIVE_REL" ] && [ -f "$f/home/$LIVE_REL" ]; then
  ok
else
  fail "materialize left the live path a symlink"
fi
check "materialize preserved the resolved content" \
  "$(cat "$f/home/$LIVE_REL")" "resolved uncommitted content"
check "materialize did not touch the symlink target" \
  "$(cat "$f/target/config.kdl")" "resolved uncommitted content"

# --- materialize: absent -> seeded from the record -------------------------
f="$scratch/mat-absent"; make_fixture "$f"
run_cfg "$f" materialize >/dev/null
if cmp -s "$f/container/main/$RECORD_REL" "$f/home/$LIVE_REL"; then
  ok
else
  fail "materialize did not seed the absent live file"
fi

# --- materialize: existing regular file is never clobbered -----------------
f="$scratch/mat-regular"; make_fixture "$f"
mkdir -p "$f/home/.config/niri"
printf 'the user tuned this\n' >"$f/home/$LIVE_REL"
run_cfg "$f" materialize >/dev/null
check "materialize left the user's file alone" \
  "$(cat "$f/home/$LIVE_REL")" "the user tuned this"

# --- materialize is idempotent across a second run -------------------------
for case_dir in mat-symlink mat-absent mat-regular; do
  before_sum="$(sha256sum "$scratch/$case_dir/home/$LIVE_REL" | cut -d' ' -f1)"
  run_cfg "$scratch/$case_dir" materialize >/dev/null
  after_sum="$(sha256sum "$scratch/$case_dir/home/$LIVE_REL" | cut -d' ' -f1)"
  check "$case_dir second run is a no-op" "$after_sum" "$before_sum"
  if [ ! -L "$scratch/$case_dir/home/$LIVE_REL" ]; then
    ok
  else
    fail "$case_dir second run reintroduced a symlink"
  fi
done

# the materialized file must be writable — the whole point is live tuning
if [ -w "$scratch/mat-absent/home/$LIVE_REL" ]; then
  ok
else
  fail "seeded live file is not writable"
fi

# --- registry generality: one row is all a new volatile file needs ---------
if grep -Eq '^ *"niri\|\.config/niri/config\.kdl\|dotfiles/niri/config\.kdl"' "$TARGET"; then
  ok
else
  fail "registry row for niri not found in the expected name|live|record shape"
fi

# --- CLI hygiene -----------------------------------------------------------
if HOME="$scratch/insync/home" CFG_REPO="$scratch/insync/container/main" \
   "$TARGET" bogus-verb >/dev/null 2>&1; then
  fail "unknown verb exited 0"
else
  ok
fi
if HOME="$scratch/insync/home" CFG_REPO="$scratch/insync/container/main" \
   "$TARGET" --help >/dev/null 2>&1; then
  ok
else
  fail "--help exited nonzero"
fi
if HOME="$scratch/insync/home" CFG_REPO="$scratch/nonexistent" \
   "$TARGET" status >/dev/null 2>&1; then
  fail "an invalid CFG_REPO was accepted"
else
  ok
fi

if [ "$fail_count" -eq 0 ]; then
  printf 'cfg tests: PASS (%d checks)\n' "$pass"
else
  printf 'cfg tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
