#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/firn-sync-local-inputs"
REBUILD="$(cd "$(dirname "$0")" && pwd)/firn-cmds/rebuild.rkt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git_config() {
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.invalid
}

make_repo() {
  local path="$1"
  git init -q -b main "$path"
  git_config "$path"
  printf 'v1\n' >"$path/source"
  git -C "$path" add source
  git -C "$path" commit -qm initial
}

make_repo "$TMP/firn"
for input in beagle fram north; do make_repo "$TMP/$input"; done

for input in beagle fram north; do
  rev="$(git -C "$TMP/$input" rev-parse HEAD)"
  jq -n --arg input "$input" --arg rev "$rev" \
    '{nodes:{($input):{locked:{rev:$rev}}}}' >"$TMP/$input.json"
done
jq -s '{nodes:(map(.nodes)|add)}' \
  "$TMP/beagle.json" "$TMP/fram.json" "$TMP/north.json" \
  >"$TMP/firn/flake.lock"
git -C "$TMP/firn" add flake.lock
git -C "$TMP/firn" commit -qm lock

mkdir "$TMP/bin"
cat >"$TMP/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root=''
inputs=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --flake) root="$2"; shift 2 ;;
    beagle|fram|north) inputs+=("$1"); shift ;;
    *) shift ;;
  esac
done
for input in "${inputs[@]}"; do
  upper="$(printf '%s' "$input" | tr '[:lower:]' '[:upper:]')"
  var="FIRN_${upper}_REPO"
  if [ "${FAKE_NIX_ADVANCE_INPUT:-}" = "$input" ]; then
    printf 'nix-resolution-race\n' >>"${!var}/source"
    git -C "${!var}" add source
    git -C "${!var}" commit -qm nix-resolution-race
  fi
  rev="$(git -C "${!var}" rev-parse --verify 'refs/heads/main^{commit}')"
  [ "${FAKE_NIX_WRONG:-0}" != 1 ] || rev=0000000000000000000000000000000000000000
  tmp="$root/flake.lock.tmp"
  jq --arg input "$input" --arg rev "$rev" '.nodes[$input].locked.rev=$rev' "$root/flake.lock" >"$tmp"
  mv "$tmp" "$root/flake.lock"
done
if [ -n "${FAKE_NIX_REWRITE_UNREQUESTED:-}" ]; then
  tmp="$root/flake.lock.tmp"
  jq --arg input "$FAKE_NIX_REWRITE_UNREQUESTED" \
    '.nodes[$input].locked.rev="0000000000000000000000000000000000000000"' \
    "$root/flake.lock" >"$tmp"
  mv "$tmp" "$root/flake.lock"
fi
EOF
chmod +x "$TMP/bin/nix"

export FIRN_REPO="$TMP/firn"
export FIRN_BEAGLE_REPO="$TMP/beagle"
export FIRN_FRAM_REPO="$TMP/fram"
export FIRN_NORTH_REPO="$TMP/north"
export PATH="$TMP/bin:$PATH"

lock_rev() { jq -r --arg i "$1" '.nodes[$i].locked.rev' "$TMP/firn/flake.lock"; }
lock_clean() {
  git -C "$TMP/firn" diff --quiet -- flake.lock &&
  git -C "$TMP/firn" diff --cached --quiet -- flake.lock
}
assert_no_local_plan() {
  local result="$1" context="$2"
  if grep -Eq '^plan (beagle|fram|north) ' <<<"$result"; then
    printf '%s unexpectedly produced a local-input plan\n' "$context" >&2
    exit 1
  fi
}

# Explicit release builds consume the exact requested object even if local main
# advances; ordinary planning contains no local inputs.
grep -Fq '(format "git+file://~a?ref=main&rev=~a"' "$REBUILD"
grep -Fxq 'PLAN_INPUTS=()' "$SCRIPT"
grep -Fxq 'LOCAL_INPUTS=(beagle fram north)' "$SCRIPT"

# All current: no plan lines, nothing mutated.
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "current inputs"
lock_clean

# Tool/editor state is not part of a Git input snapshot and must not matter.
printf 'local state\n' >"$TMP/beagle/untracked"
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "untracked input state"

# Committed North and Beagle main moves never enter the ordinary rebuild plan,
# and planning never mutates either lock.
printf 'v2\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm update
old_north="$(lock_rev north)"
new_north="$(git -C "$TMP/north" rev-parse HEAD)"
printf 'v2\n' >>"$TMP/beagle/source"
git -C "$TMP/beagle" add source
git -C "$TMP/beagle" commit -qm update
old_beagle="$(lock_rev beagle)"
new_beagle="$(git -C "$TMP/beagle" rev-parse HEAD)"
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "committed North and Beagle main advances"
lock_clean
[ "$(lock_rev north)" = "$old_north" ]
[ "$(lock_rev beagle)" = "$old_beagle" ]

# Explicit settlement promotes an exactly verified North target and makes the
# mechanical commit even though --plan deliberately excluded it.
before_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$($SCRIPT --commit "north=$new_north")"
grep -q 'north promoted' <<<"$output"
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq $((before_count + 1)) ]
[ "$(lock_rev north)" = "$new_north" ]
lock_clean

# An EXIT/TERM crash immediately after the mechanical commit must preserve the
# exact promoted lock already in HEAD. The handler heals index/worktree to that
# commit, removes its recovery files, and the next run sees a current pin.
printf 'v3\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm post-commit-crash-target
crash_north="$(git -C "$TMP/north" rev-parse HEAD)"
crash_count_before="$(git -C "$TMP/firn" rev-list --count HEAD)"
mkdir "$TMP/recovery-tmp"
if output="$(
  TMPDIR="$TMP/recovery-tmp" \
  FIRN_INJECT_CRASH_AFTER_COMMIT=1 \
    "$SCRIPT" --commit "north=$crash_north" 2>&1
)"; then
  printf 'injected post-commit crash unexpectedly returned success\n' >&2
  exit 1
fi
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq $((crash_count_before + 1)) ]
[ "$(lock_rev north)" = "$crash_north" ]
lock_clean
[ -z "$(find "$TMP/recovery-tmp" -mindepth 1 -print -quit)" ]
output="$($SCRIPT --commit "north=$crash_north")"
grep -q 'north no longer promotable; deferring' <<<"$output"

# The internal commit contract is explicit and rejects malformed target specs
# before any lock mutation.
if output="$("$SCRIPT" --commit north 2>&1)"; then
  printf 'expected missing commit revision to fail\n' >&2
  exit 1
fi
grep -q 'must be <input>=<verified-rev>' <<<"$output"
if output="$("$SCRIPT" --commit "other=$new_north" 2>&1)"; then
  printf 'expected unknown local input to fail\n' >&2
  exit 1
fi
grep -q "unknown local input 'other'" <<<"$output"
if output="$("$SCRIPT" --commit 'north=not-a-revision' 2>&1)"; then
  printf 'expected malformed revision to fail\n' >&2
  exit 1
fi
grep -q 'invalid verified revision' <<<"$output"
if output="$("$SCRIPT" --commit "north=$new_north" "north=$new_north" 2>&1)"; then
  printf 'expected duplicate local input to fail\n' >&2
  exit 1
fi
grep -q 'duplicate --commit target' <<<"$output"
lock_clean

# A lock refresh that lands on the wrong rev defers (exit 0) and restores.
printf 'v3\n' >>"$TMP/beagle/source"
git -C "$TMP/beagle" add source
git -C "$TMP/beagle" commit -qm update-verify-failure
original_lock="$(sha256sum "$TMP/firn/flake.lock")"
count_before="$(git -C "$TMP/firn" rev-list --count HEAD)"
new_beagle="$(git -C "$TMP/beagle" rev-parse HEAD)"
output="$(FAKE_NIX_WRONG=1 "$SCRIPT" --commit "beagle=$new_beagle")"
grep -q 'deferring' <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$original_lock" ]
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq "$count_before" ]
lock_clean

# Commit-hook failure after staging also defers and restores.
mkdir -p "$TMP/firn/.git/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/firn/.git/hooks/pre-commit"
chmod +x "$TMP/firn/.git/hooks/pre-commit"
output="$($SCRIPT --commit "beagle=$new_beagle")"
grep -q 'deferring' <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$original_lock" ]
lock_clean
rm "$TMP/firn/.git/hooks/pre-commit"

# Another session's WIP never blocks or leaks, and a pending Beagle release
# stays out of the ordinary plan.
printf 'dirty\n' >>"$TMP/fram/source"
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "dirty Fram checkout and pending Beagle release"

# With dirty Fram main ahead of the pin, ordinary planning remains empty while
# explicit settlement promotes only the exact committed-main revision.
git -C "$TMP/fram" add source
git -C "$TMP/fram" commit -qm wip-base
printf 'more wip\n' >>"$TMP/fram/source"
new_fram="$(git -C "$TMP/fram" rev-parse 'refs/heads/main^{commit}')"
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "advanced dirty Fram main"
output="$($SCRIPT --commit "fram=$new_fram")"
grep -q 'fram promoted' <<<"$output"
[ "$(lock_rev fram)" = "$new_fram" ]
grep -q '^ M source$' < <(git -C "$TMP/fram" status --short)
if git -C "$TMP/fram" show 'refs/heads/main:source' | grep -q 'more wip'; then
  printf 'dirty worktree content leaked into committed main\n' >&2
  exit 1
fi

# A feature-only commit never enters ordinary planning and is rejected by
# explicit settlement because it is not the committed local main target.
git -C "$TMP/fram" checkout -q -- source
git -C "$TMP/fram" checkout -qb feature
printf 'feature\n' >>"$TMP/fram/source"
git -C "$TMP/fram" add source
git -C "$TMP/fram" commit -qm feature-only
feature_fram="$(git -C "$TMP/fram" rev-parse HEAD)"
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "feature-only Fram commit"
before_feature_lock="$(sha256sum "$TMP/firn/flake.lock")"
before_feature_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$($SCRIPT --commit "fram=$feature_fram")"
grep -q 'not built target.*deferring' <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$before_feature_lock" ]
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq "$before_feature_count" ]
lock_clean

# Another worktree may advance local main while the developer remains on a
# dirty feature checkout. The new committed main remains absent from ordinary
# planning and promotes only through explicit settlement; feature HEAD and dirty
# bytes remain excluded.
git -C "$TMP/fram" worktree add -q "$TMP/fram-main" main
printf 'main-from-other-worktree\n' >>"$TMP/fram-main/source"
git -C "$TMP/fram-main" add source
git -C "$TMP/fram-main" commit -qm main-from-other-worktree
advanced_main_fram="$(git -C "$TMP/fram-main" rev-parse HEAD)"
git -C "$TMP/fram" worktree remove "$TMP/fram-main"
printf 'dirty-feature-only\n' >>"$TMP/fram/source"
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "advanced Fram main beside a dirty feature checkout"
if grep -q "$feature_fram" <<<"$output"; then
  printf 'feature-only HEAD appeared in the local-main plan\n' >&2
  exit 1
fi
output="$($SCRIPT --commit "fram=$advanced_main_fram")"
grep -q 'fram promoted' <<<"$output"
[ "$(lock_rev fram)" = "$advanced_main_fram" ]
grep -q '^ M source$' < <(git -C "$TMP/fram" status --short)

# Back on clean Fram main, explicit settlement accepts the exactly verified
# Beagle target that ordinary planning excluded.
git -C "$TMP/fram" checkout -q -- source
git -C "$TMP/fram" checkout -q main
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "already-settled Fram main"
output="$($SCRIPT --commit "beagle=$new_beagle")"
grep -q 'beagle promoted' <<<"$output"
[ "$(lock_rev fram)" = "$(git -C "$TMP/fram" rev-parse HEAD)" ]
[ "$(lock_rev beagle)" = "$(git -C "$TMP/beagle" rev-parse HEAD)" ]
lock_clean

# A commit landing after an exact-revision build is not the revision that was
# verified, so settlement defers before nix can rewrite the lock.
printf 'v4\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm planned
planned_north="$(git -C "$TMP/north" rev-parse HEAD)"
output="$($SCRIPT --plan)"
assert_no_local_plan "$output" "verified North target"
printf 'v5\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm raced
before_race_lock="$(lock_rev north)"
output="$($SCRIPT --commit "north=$planned_north")"
grep -q 'not built target.*deferring' <<<"$output"
[ "$(lock_rev north)" = "$before_race_lock" ]
lock_clean

# A main advance inside `nix flake update` happens after commit preflight. The
# post-resolution check catches it, restores the whole lock, and commits
# nothing; the newly resolved but unbuilt revision never becomes the pin.
planned_north="$(git -C "$TMP/north" rev-parse 'refs/heads/main^{commit}')"
before_resolution_race_hash="$(sha256sum "$TMP/firn/flake.lock")"
before_resolution_race_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$(FAKE_NIX_ADVANCE_INPUT=north "$SCRIPT" --commit "north=$planned_north")"
grep -Eq 'moved to|raced to' <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$before_resolution_race_hash" ]
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq "$before_resolution_race_count" ]
lock_clean

# A targeted update may not rewrite any part of an unrequested local pin. The
# integrity set must dynamically catch Fram even though the planning set is empty.
planned_north="$(git -C "$TMP/north" rev-parse 'refs/heads/main^{commit}')"
before_unrequested_hash="$(sha256sum "$TMP/firn/flake.lock")"
before_unrequested_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
unrequested_input=fram
output="$(FAKE_NIX_REWRITE_UNREQUESTED="$unrequested_input" "$SCRIPT" --commit "north=$planned_north")"
grep -q "rewrote unrequested local input $unrequested_input.*deferring" <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$before_unrequested_hash" ]
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq "$before_unrequested_count" ]
lock_clean

# Missing local main is an explicit settlement hold, not a fallback to feature
# HEAD.
printf 'v4\n' >>"$TMP/beagle/source"
git -C "$TMP/beagle" add source
git -C "$TMP/beagle" commit -qm missing-main-target
missing_main_beagle="$(git -C "$TMP/beagle" rev-parse 'refs/heads/main^{commit}')"
git -C "$TMP/beagle" checkout -qb missing-main-probe
git -C "$TMP/beagle" branch -D main >/dev/null
before_missing_hash="$(sha256sum "$TMP/firn/flake.lock")"
before_missing_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$($SCRIPT --commit "beagle=$missing_main_beagle")"
grep -q 'beagle local refs/heads/main is missing.*built target.*not promotable, deferring' <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$before_missing_hash" ]
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq "$before_missing_count" ]
git -C "$TMP/beagle" branch main "$missing_main_beagle"
git -C "$TMP/beagle" checkout -q main
git -C "$TMP/beagle" branch -D missing-main-probe >/dev/null

# A rewound or divergent local main can never downgrade/replace the verified
# pin. Prove both relationships while keeping the active checkout off main.
locked_beagle="$(lock_rev beagle)"
beagle_parent="$(git -C "$TMP/beagle" rev-parse "$locked_beagle^")"
git -C "$TMP/beagle" checkout -qb non-ff-probe "$beagle_parent"
git -C "$TMP/beagle" branch -f main "$beagle_parent"
output="$($SCRIPT --commit "beagle=$missing_main_beagle")"
grep -q 'beagle local main.*behind verified.*non-fast-forward not promoted.*built target.*not promotable, deferring' <<<"$output"
printf 'divergent\n' >>"$TMP/beagle/source"
git -C "$TMP/beagle" add source
git -C "$TMP/beagle" commit -qm divergent
git -C "$TMP/beagle" branch -f main HEAD
output="$($SCRIPT --commit "beagle=$missing_main_beagle")"
grep -q 'beagle local main.*diverged from verified.*non-fast-forward not promoted.*built target.*not promotable, deferring' <<<"$output"
git -C "$TMP/beagle" branch -f main "$missing_main_beagle"
git -C "$TMP/beagle" checkout -q main
git -C "$TMP/beagle" branch -D non-ff-probe >/dev/null

# A foreign edit to the firn lock itself defers promotion, never blocks.
new_north="$(git -C "$TMP/north" rev-parse 'refs/heads/main^{commit}')"
printf ' \n' >>"$TMP/firn/flake.lock"
output="$($SCRIPT --commit "north=$new_north")"
grep -q 'deferring' <<<"$output"
git -C "$TMP/firn" checkout -q -- flake.lock

printf 'ok: firn-sync-local-inputs\n'
