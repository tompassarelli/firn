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
for input in beagle fram north; do make_repo "$TMP/$input"; done

for input in beagle fram north; do
  rev="$(git -C "$TMP/$input" rev-parse HEAD)"
  jq -n --arg input "$input" --arg rev "$rev" \
    '{nodes:{($input):{locked:{rev:$rev}}}}' >"$TMP/$input.json"
done
jq -s '{nodes:(map(.nodes)|add)}' "$TMP/beagle.json" "$TMP/fram.json" "$TMP/north.json" >"$TMP/firn/flake.lock"
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
! grep -q '^plan ' <<<"$output"
lock_clean

# Tool/editor state is not part of a Git input snapshot and must not matter.
printf 'local state\n' >"$TMP/beagle/untracked"
output="$($SCRIPT --plan)"
! grep -q '^plan ' <<<"$output"

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
output="$($SCRIPT --commit north)"
grep -q 'north promoted' <<<"$output"
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq $((before_count + 1)) ]
[ "$(lock_rev north)" = "$new_north" ]
lock_clean

# A lock refresh that lands on the wrong rev defers (exit 0) and restores.
printf 'v3\n' >>"$TMP/beagle/source"
git -C "$TMP/beagle" add source
git -C "$TMP/beagle" commit -qm update-verify-failure
original_lock="$(sha256sum "$TMP/firn/flake.lock")"
count_before="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$(FAKE_NIX_WRONG=1 "$SCRIPT" --commit beagle)"
grep -q 'deferring' <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$original_lock" ]
[ "$(git -C "$TMP/firn" rev-list --count HEAD)" -eq "$count_before" ]
lock_clean

# Commit-hook failure after staging also defers and restores.
mkdir -p "$TMP/firn/.git/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/firn/.git/hooks/pre-commit"
chmod +x "$TMP/firn/.git/hooks/pre-commit"
output="$($SCRIPT --commit beagle)"
grep -q 'deferring' <<<"$output"
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$original_lock" ]
lock_clean
rm "$TMP/firn/.git/hooks/pre-commit"

# Another session's WIP never blocks: the dirty input holds its verified pin
# while a clean input still plans its move (beagle is still pending here).
printf 'dirty\n' >>"$TMP/fram/source"
output="$($SCRIPT --plan)"
grep -q 'fram.*dirty tree' <<<"$output"
! grep -q '^plan fram ' <<<"$output"
grep -q '^plan beagle ' <<<"$output"

# Dirty repo whose HEAD moved ahead of the pin: hold the old verified rev.
git -C "$TMP/fram" add source
git -C "$TMP/fram" commit -qm wip-base
printf 'more wip\n' >>"$TMP/fram/source"
output="$($SCRIPT --plan)"
grep -q 'fram.*holding verified' <<<"$output"
! grep -q '^plan fram ' <<<"$output"

# Non-main checkout holds too — refresh only promotes commits from main.
git -C "$TMP/fram" checkout -q -- source
git -C "$TMP/fram" checkout -qb feature
output="$($SCRIPT --plan)"
grep -q 'fram.*not main' <<<"$output"
! grep -q '^plan fram ' <<<"$output"

# Back on clean main, the held commit plans and promotes normally.
git -C "$TMP/fram" checkout -q main
output="$($SCRIPT --plan)"
grep -q '^plan fram ' <<<"$output"
output="$($SCRIPT --commit fram beagle)"
grep -q 'fram promoted' <<<"$output"
grep -q 'beagle promoted' <<<"$output"
[ "$(lock_rev fram)" = "$(git -C "$TMP/fram" rev-parse HEAD)" ]
[ "$(lock_rev beagle)" = "$(git -C "$TMP/beagle" rev-parse HEAD)" ]
lock_clean

# A foreign edit to the firn lock itself defers promotion, never blocks.
printf 'v4\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm another
printf ' \n' >>"$TMP/firn/flake.lock"
output="$($SCRIPT --commit north)"
grep -q 'deferring' <<<"$output"
git -C "$TMP/firn" checkout -q -- flake.lock

printf 'ok: firn-sync-local-inputs\n'
