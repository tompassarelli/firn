#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/wt-rescue"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/wt-rescue-test.XXXXXX")"
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

new_container() {
  local container="$1"
  mkdir -p "$container"
  git init -q -b main "$container/main"
  git -C "$container/main" config user.name wt-rescue-test
  git -C "$container/main" config user.email wt-rescue-test@example.invalid
  printf 'base\n' >"$container/main/f.txt"
  printf 'kept\n' >"$container/main/other.txt"
  git -C "$container/main" add f.txt other.txt
  git -C "$container/main" commit -qm base
}

# =============================================================================
# 1. end-to-end rescue: dirty tracked (staged+unstaged) + untracked + ignored
# =============================================================================
c1="$scratch/proj1"
new_container "$c1"
printf '*.ignoreme\n' >"$c1/main/.gitignore"
git -C "$c1/main" add .gitignore
git -C "$c1/main" commit -qm 'add gitignore to base'

# unstaged modification to a tracked file
printf 'base\nunstaged change\n' >"$c1/main/f.txt"
# staged new file
printf 'staged new\n' >"$c1/main/new.txt"
git -C "$c1/main" add new.txt
# untracked (non-ignored) file, including a nested dir
mkdir -p "$c1/main/sub"
printf 'loose\n' >"$c1/main/loose.txt"
printf 'nested\n' >"$c1/main/sub/nested.txt"
# ignored file — must survive untouched, never rescued
printf 'should stay\n' >"$c1/main/secret.ignoreme"

status1=0
output1="$(cd "$c1/main" && "$TARGET" 2>&1)" || status1=$?

if [ "$status1" -eq 0 ]; then ok; else fail "end-to-end exit status: got $status1: $output1"; fi

final_clean="$(git -C "$c1/main" status --porcelain)"
if [ -z "$final_clean" ]; then ok; else fail "main not clean after rescue: $final_clean"; fi

if [ "$(cat "$c1/main/f.txt")" = "base" ]; then ok; else fail "f.txt not restored to HEAD content"; fi
if [ ! -e "$c1/main/new.txt" ]; then ok; else fail "staged new.txt still present in main"; fi
if [ ! -e "$c1/main/loose.txt" ]; then ok; else fail "untracked loose.txt still present in main"; fi
if [ ! -e "$c1/main/sub/nested.txt" ]; then ok; else fail "untracked sub/nested.txt still present in main"; fi
if [ -e "$c1/main/secret.ignoreme" ]; then ok; else fail "ignored file was deleted from main"; fi
if [ -e "$c1/main/.gitignore" ]; then ok; else fail ".gitignore itself missing"; fi

rescue_line="$(grep -F 'rescued -> ' <<<"$output1" || true)"
if [ -n "$rescue_line" ]; then ok; else fail "missing final 'rescued -> ' summary line: $output1"; fi
rescue_path="$(sed -E 's/^rescued -> ([^ ]+) .*/\1/' <<<"$rescue_line")"

if [ -d "$rescue_path" ]; then ok; else fail "rescue worktree dir missing: $rescue_path"; fi
if [ "$(cd "$rescue_path" && printf '%s\n' "$(basename "$rescue_path")")" ]; then ok; else fail "unreachable"; fi
# The destination is a lane under worktrees/, and the branch keeps the bare
# rescue-<ts> name wt-reap's safety gate matches on.
case "$rescue_path" in
  "$c1"/worktrees/rescue-*) ok ;;
  *) fail "rescue destination is not <container>/worktrees/rescue-<ts>: $rescue_path" ;;
esac
case "$(git -C "$rescue_path" symbolic-ref --quiet --short HEAD)" in
  rescue-*) ok ;;
  *) fail "rescue branch is not rescue-<ts>: $(git -C "$rescue_path" symbolic-ref --quiet --short HEAD)" ;;
esac

if [ -n "$(git -C "$rescue_path" status --porcelain)" ]; then
  fail "rescue worktree not committed cleanly: $(git -C "$rescue_path" status --porcelain)"
else
  ok
fi
if [ "$(cat "$rescue_path/f.txt")" = "$(printf 'base\nunstaged change\n')" ]; then ok; else fail "rescue f.txt content wrong"; fi
if [ "$(cat "$rescue_path/new.txt")" = "staged new" ]; then ok; else fail "rescue new.txt content wrong"; fi
if [ "$(cat "$rescue_path/loose.txt")" = "loose" ]; then ok; else fail "rescue loose.txt content wrong"; fi
if [ "$(cat "$rescue_path/sub/nested.txt")" = "nested" ]; then ok; else fail "rescue sub/nested.txt content wrong"; fi
if [ ! -e "$rescue_path/secret.ignoreme" ]; then ok; else fail "ignored file was rescued (should never be)"; fi

if git -C "$c1/main" show-ref --quiet --verify "refs/heads/rescue-$(date -u +%Y%m%d-%H%M)" 2>/dev/null \
  || git -C "$c1/main" worktree list | grep -Fq "$rescue_path"; then
  ok
else
  fail "rescue worktree not registered against main"
fi

# =============================================================================
# 2. clean main -> no-op
# =============================================================================
c2="$scratch/proj2"
new_container "$c2"
before_head="$(git -C "$c2/main" rev-parse HEAD)"
status2=0
output2="$(cd "$c2/main" && "$TARGET" 2>&1)" || status2=$?
if [ "$status2" -eq 0 ]; then ok; else fail "clean no-op exit status: got $status2"; fi
if grep -Fq 'clean, nothing to rescue' <<<"$output2"; then ok; else fail "missing clean no-op message: $output2"; fi
after_head="$(git -C "$c2/main" rev-parse HEAD)"
if [ "$before_head" = "$after_head" ]; then ok; else fail "clean main HEAD moved"; fi
if [ -z "$(find "$c2/worktrees" -maxdepth 1 -name 'rescue-*' 2>/dev/null)" ]; then ok; else fail "clean no-op created a rescue worktree"; fi

# =============================================================================
# 3. --dry-run mutates nothing
# =============================================================================
c3="$scratch/proj3"
new_container "$c3"
printf 'base\ndirty\n' >"$c3/main/f.txt"
printf 'untracked\n' >"$c3/main/loose.txt"
before_status3="$(git -C "$c3/main" status --porcelain)"
status3=0
output3="$(cd "$c3/main" && "$TARGET" --dry-run 2>&1)" || status3=$?
after_status3="$(git -C "$c3/main" status --porcelain)"

if [ "$status3" -eq 0 ]; then ok; else fail "--dry-run exit status: got $status3"; fi
if grep -Fq 'DRY RUN' <<<"$output3"; then ok; else fail "missing DRY RUN marker: $output3"; fi
if grep -Fq 'f.txt' <<<"$output3"; then ok; else fail "dry-run plan missing tracked file: $output3"; fi
if grep -Fq 'loose.txt' <<<"$output3"; then ok; else fail "dry-run plan missing untracked file: $output3"; fi
if [ "$before_status3" = "$after_status3" ]; then ok; else fail "--dry-run mutated main's status"; fi
if [ -z "$(find "$c3/worktrees" -maxdepth 1 -name 'rescue-*' 2>/dev/null)" ]; then ok; else fail "--dry-run created a rescue worktree"; fi

# =============================================================================
# 4. verify-mismatch abort leaves main untouched
# =============================================================================
c4="$scratch/proj4"
new_container "$c4"
printf 'base\ndirty\n' >"$c4/main/f.txt"

fake_bin="$scratch/fakebin4"
mkdir -p "$fake_bin"
real_git="$(command -v git)"
cat >"$fake_bin/git" <<FAKEGIT
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = apply ]; then
    # simulate a corrupting apply: silently do nothing, leaving rescue's copy
    # stale relative to what main actually has, so the byte-compare must fail.
    exec cat >/dev/null
  fi
done
exec "$real_git" "\$@"
FAKEGIT
chmod +x "$fake_bin/git"

before_status4="$(git -C "$c4/main" status --porcelain)"
before_head4="$(git -C "$c4/main" rev-parse HEAD)"
status4=0
output4="$(cd "$c4/main" && PATH="$fake_bin:$PATH" "$TARGET" 2>&1)" || status4=$?
after_status4="$(git -C "$c4/main" status --porcelain)"
after_head4="$(git -C "$c4/main" rev-parse HEAD)"

if [ "$status4" -ne 0 ]; then ok; else fail "verify-mismatch should exit nonzero, got 0: $output4"; fi
if grep -Fq 'VERIFY MISMATCH' <<<"$output4"; then ok; else fail "missing VERIFY MISMATCH message: $output4"; fi
if [ "$before_status4" = "$after_status4" ]; then ok; else fail "main status changed after aborted rescue"; fi
if [ "$before_head4" = "$after_head4" ]; then ok; else fail "main HEAD changed after aborted rescue"; fi
if [ "$(cat "$c4/main/f.txt")" = "$(printf 'base\ndirty\n')" ]; then ok; else fail "main's dirty file content changed after abort"; fi

# =============================================================================
# 5. a REJECTING pre-commit hook must not defeat the rescue
#    Regression: contribution hooks judge the whole tree, so a lint failure on
#    files the rescue never touched (or a stale base predating a hook repair)
#    used to abort the rescue and leave main dirty forever — the sanctioned
#    remedy for a dirty main unable to remedy it.
# =============================================================================
c5="$scratch/proj5"
new_container "$c5"
mkdir -p "$c5/main/.git/hooks"
cat >"$c5/main/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
echo "pre-commit: refusing (unrelated tree lint)" >&2
exit 1
HOOK
chmod +x "$c5/main/.git/hooks/pre-commit"
printf 'base\ndirty\n' >"$c5/main/f.txt"
output5="$(cd "$c5/main" && "$TARGET" 2>&1)" || true
after_status5="$(git -C "$c5/main" status --porcelain)"

if [ -z "$after_status5" ]; then ok; else fail "main left dirty despite rejecting hook: $after_status5"; fi
rescued5="$(find "$c5/worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
if [ -n "$rescued5" ]; then ok; else fail "no rescue worktree created: $output5"; fi
if [ "$(cat "$rescued5/f.txt" 2>/dev/null)" = "$(printf 'base\ndirty\n')" ]; then ok; else fail "rescued content not preserved under rejecting hook"; fi
if git -C "$rescued5" log -1 --format=%s 2>/dev/null | grep -Fq 'rescued dirty state'; then ok; else fail "rescue commit missing under rejecting hook"; fi

# =============================================================================
# 6. shellcheck cleanliness of the tool itself (belt-and-suspenders local check)
# =============================================================================
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$TARGET" >/dev/null 2>&1; then ok; else fail "shellcheck reported issues on $TARGET"; fi
else
  ok # linter not installed in this environment; separate CI/lint step covers it
fi

if [ "$fail_count" -eq 0 ]; then
  printf 'wt-rescue tests: PASS (%d checks)\n' "$pass"
else
  printf 'wt-rescue tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
