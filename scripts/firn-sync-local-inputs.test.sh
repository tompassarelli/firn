#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/firn-sync-local-inputs"
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
for input in beagle fram gaffer north; do make_repo "$TMP/$input"; done

for input in beagle fram gaffer north; do
  rev="$(git -C "$TMP/$input" rev-parse HEAD)"
  jq -n --arg input "$input" --arg rev "$rev" \
    '{nodes:{($input):{locked:{rev:$rev}}}}' >"$TMP/$input.json"
done
jq -s '{nodes:(map(.nodes)|add)}' \
  "$TMP/beagle.json" "$TMP/fram.json" "$TMP/gaffer.json" "$TMP/north.json" \
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
    beagle|fram|gaffer|north) inputs+=("$1"); shift ;;
    *) shift ;;
  esac
done
for input in "${inputs[@]}"; do
  upper="$(printf '%s' "$input" | tr '[:lower:]' '[:upper:]')"
  var="FIRN_${upper}_REPO"
  rev="$(git -C "${!var}" rev-parse HEAD)"
  [ "${FAKE_NIX_WRONG:-0}" != 1 ] || rev=0000000000000000000000000000000000000000
  tmp="$root/flake.lock.tmp"
  jq --arg input "$input" --arg rev "$rev" '.nodes[$input].locked.rev=$rev' "$root/flake.lock" >"$tmp"
  mv "$tmp" "$root/flake.lock"
done
EOF
chmod +x "$TMP/bin/nix"

export FIRN_REPO="$TMP/firn"
export FIRN_BEAGLE_REPO="$TMP/beagle"
export FIRN_FRAM_REPO="$TMP/fram"
export FIRN_GAFFER_REPO="$TMP/gaffer"
export FIRN_NORTH_REPO="$TMP/north"
export PATH="$TMP/bin:$PATH"

lock_rev() { jq -r --arg i "$1" '.nodes[$i].locked.rev' "$TMP/firn/flake.lock"; }
lock_clean() {
  git -C "$TMP/firn" diff --quiet -- flake.lock &&
  git -C "$TMP/firn" diff --cached --quiet -- flake.lock
}

# All current: no plan lines, nothing mutated.
output="$($SCRIPT --plan)"
grep -q 'current at' <<<"$output"
if grep -q '^plan ' <<<"$output"; then
  printf 'current inputs unexpectedly produced a plan\n' >&2
  exit 1
fi
lock_clean

# Tool/editor state is not part of a Git input snapshot and must not matter.
printf 'local state\n' >"$TMP/beagle/untracked"
output="$($SCRIPT --plan)"
if grep -q '^plan ' <<<"$output"; then
  printf 'untracked input state unexpectedly produced a plan\n' >&2
  exit 1
fi

# Gaffer is a first-class local input: committed main HEAD plans, verifies,
# promotes, and leaves no provisional lock mutation behind.
printf 'v2\n' >>"$TMP/gaffer/source"
git -C "$TMP/gaffer" add source
git -C "$TMP/gaffer" commit -qm update
old_gaffer="$(lock_rev gaffer)"
new_gaffer="$(git -C "$TMP/gaffer" rev-parse HEAD)"
output="$($SCRIPT --plan)"
grep -q "^plan gaffer $old_gaffer $new_gaffer $TMP/gaffer\$" <<<"$output"
lock_clean
[ "$(lock_rev gaffer)" = "$old_gaffer" ]
before_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$($SCRIPT --commit "gaffer=$new_gaffer")"
grep -q 'gaffer promoted' <<<"$output"
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq $((before_count + 1)) ]
[ "$(lock_rev gaffer)" = "$new_gaffer" ]
lock_clean

# A new commit on main plans a promotable move — and planning NEVER mutates.
printf 'v2\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm update
old_north="$(lock_rev north)"
new_north="$(git -C "$TMP/north" rev-parse HEAD)"
output="$($SCRIPT --plan)"
grep -q "^plan north $old_north $new_north $TMP/north\$" <<<"$output"
lock_clean
[ "$(lock_rev north)" = "$old_north" ]

# --commit promotes the verified target and makes the mechanical commit.
before_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$($SCRIPT --commit "north=$new_north")"
grep -q 'north promoted' <<<"$output"
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq $((before_count + 1)) ]
[ "$(lock_rev north)" = "$new_north" ]
lock_clean

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

# Another session's WIP never blocks and never leaks. At the current pin it is
# merely reported as excluded, while a clean input still plans its move.
printf 'dirty\n' >>"$TMP/fram/source"
output="$($SCRIPT --plan)"
grep -q 'fram.*tracked WIP excluded' <<<"$output"
if grep -q '^plan fram ' <<<"$output"; then
  printf 'dirty worktree at the locked commit unexpectedly produced a plan\n' >&2
  exit 1
fi
grep -q '^plan beagle ' <<<"$output"

# Dirty main whose HEAD moved ahead of the pin promotes committed HEAD only.
git -C "$TMP/fram" add source
git -C "$TMP/fram" commit -qm wip-base
printf 'more wip\n' >>"$TMP/fram/source"
new_fram="$(git -C "$TMP/fram" rev-parse HEAD)"
output="$($SCRIPT --plan)"
grep -q 'fram.*tracked WIP excluded' <<<"$output"
grep -q "^plan fram .* $new_fram $TMP/fram\$" <<<"$output"
output="$($SCRIPT --commit "fram=$new_fram")"
grep -q 'fram promoted' <<<"$output"
[ "$(lock_rev fram)" = "$new_fram" ]
grep -q '^ M source$' < <(git -C "$TMP/fram" status --short)
if git -C "$TMP/fram" show HEAD:source | grep -q 'more wip'; then
  printf 'dirty worktree content leaked into committed HEAD\n' >&2
  exit 1
fi

# Non-main checkout holds too — refresh only promotes commits from main.
git -C "$TMP/fram" checkout -q -- source
git -C "$TMP/fram" checkout -qb feature
printf 'feature\n' >>"$TMP/fram/source"
git -C "$TMP/fram" add source
git -C "$TMP/fram" commit -qm feature-only
output="$($SCRIPT --plan)"
grep -q 'fram.*not main' <<<"$output"
if grep -q '^plan fram ' <<<"$output"; then
  printf 'feature-branch input unexpectedly produced a plan\n' >&2
  exit 1
fi

# Back on clean main, only the pending clean input promotes.
git -C "$TMP/fram" checkout -q main
output="$($SCRIPT --plan)"
if grep -q '^plan fram ' <<<"$output"; then
  printf 'already-promoted main input unexpectedly produced a plan\n' >&2
  exit 1
fi
output="$($SCRIPT --commit "beagle=$new_beagle")"
grep -q 'beagle promoted' <<<"$output"
[ "$(lock_rev fram)" = "$(git -C "$TMP/fram" rev-parse HEAD)" ]
[ "$(lock_rev beagle)" = "$(git -C "$TMP/beagle" rev-parse HEAD)" ]
lock_clean

# A commit landing after plan is not the revision that was built, so commit
# defers before nix can rewrite the lock.
printf 'v4\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm planned
planned_north="$(git -C "$TMP/north" rev-parse HEAD)"
output="$($SCRIPT --plan)"
grep -q "^plan north .* $planned_north $TMP/north\$" <<<"$output"
printf 'v5\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm raced
before_race_lock="$(lock_rev north)"
output="$($SCRIPT --commit "north=$planned_north")"
grep -q 'not built target.*deferring' <<<"$output"
[ "$(lock_rev north)" = "$before_race_lock" ]
lock_clean

# A foreign edit to the firn lock itself defers promotion, never blocks.
new_north="$(git -C "$TMP/north" rev-parse HEAD)"
printf ' \n' >>"$TMP/firn/flake.lock"
output="$($SCRIPT --commit "north=$new_north")"
grep -q 'deferring' <<<"$output"
git -C "$TMP/firn" checkout -q -- flake.lock

printf 'ok: firn-sync-local-inputs\n'
