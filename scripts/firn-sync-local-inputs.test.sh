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

output="$($SCRIPT --commit)"
grep -q 'already current' <<<"$output"

# Tool/editor state is not part of a Git input snapshot and must not block.
printf 'local state\n' >"$TMP/beagle/untracked"
output="$($SCRIPT --commit)"
grep -q 'already current' <<<"$output"

printf 'v2\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm update
before_count="$(git -C "$TMP/firn" rev-list --count HEAD)"

# Provisional refresh advances the worktree pointer but never stages/commits it.
output="$($SCRIPT --provisional)"
provisional_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
[ "$provisional_count" -eq "$before_count" ]
git -C "$TMP/firn" diff --quiet -- flake.lock && exit 1
git -C "$TMP/firn" diff --cached --quiet -- flake.lock
git -C "$TMP/firn" restore flake.lock

output="$($SCRIPT --commit)"
after_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
[ "$after_count" -eq $((before_count + 1)) ]
grep -q 'north.*→' <<<"$output"
[ "$(jq -r '.nodes.north.locked.rev' "$TMP/firn/flake.lock")" = "$(git -C "$TMP/north" rev-parse HEAD)" ]

# Verification failure restores both worktree and index to the original lock.
printf 'v3\n' >>"$TMP/beagle/source"
git -C "$TMP/beagle" add source
git -C "$TMP/beagle" commit -qm update-verify-failure
original_lock="$(sha256sum "$TMP/firn/flake.lock")"
if FAKE_NIX_WRONG=1 "$SCRIPT" --provisional >"$TMP/out" 2>"$TMP/err"; then
  echo 'expected refreshed-revision verification failure' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$original_lock" ]
git -C "$TMP/firn" diff --quiet -- flake.lock
git -C "$TMP/firn" diff --cached --quiet -- flake.lock

# Commit-hook failure after staging also restores worktree and index.
mkdir -p "$TMP/firn/.git/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/firn/.git/hooks/pre-commit"
chmod +x "$TMP/firn/.git/hooks/pre-commit"
if "$SCRIPT" --commit >"$TMP/out" 2>"$TMP/err"; then
  echo 'expected mechanical commit failure' >&2
  exit 1
fi
[ "$(sha256sum "$TMP/firn/flake.lock")" = "$original_lock" ]
git -C "$TMP/firn" diff --quiet -- flake.lock
git -C "$TMP/firn" diff --cached --quiet -- flake.lock
rm "$TMP/firn/.git/hooks/pre-commit"

# Another session's WIP never blocks: the dirty input holds its verified pin
# while clean inputs still refresh (beagle has a pending commit at this point).
printf 'dirty\n' >>"$TMP/fram/source"
output="$($SCRIPT --commit)"
grep -q 'fram.*dirty tree' <<<"$output"
grep -q 'beagle.*→' <<<"$output"
[ "$(jq -r '.nodes.beagle.locked.rev' "$TMP/firn/flake.lock")" = "$(git -C "$TMP/beagle" rev-parse HEAD)" ]

# Dirty repo whose HEAD moved ahead of the pin: the old verified rev is held.
git -C "$TMP/fram" add source
git -C "$TMP/fram" commit -qm wip-base
printf 'more wip\n' >>"$TMP/fram/source"
locked_fram="$(jq -r '.nodes.fram.locked.rev' "$TMP/firn/flake.lock")"
output="$($SCRIPT --commit)"
grep -q 'fram.*holding verified' <<<"$output"
[ "$(jq -r '.nodes.fram.locked.rev' "$TMP/firn/flake.lock")" = "$locked_fram" ]

# Non-main checkout holds too — refresh only promotes commits from main.
git -C "$TMP/fram" checkout -q -- source
git -C "$TMP/fram" checkout -qb feature
output="$($SCRIPT --commit)"
grep -q 'fram.*not main' <<<"$output"
[ "$(jq -r '.nodes.fram.locked.rev' "$TMP/firn/flake.lock")" = "$locked_fram" ]

# Back on clean main, the held commit promotes normally.
git -C "$TMP/fram" checkout -q main
output="$($SCRIPT --commit)"
grep -q 'fram.*→' <<<"$output"
[ "$(jq -r '.nodes.fram.locked.rev' "$TMP/firn/flake.lock")" = "$(git -C "$TMP/fram" rev-parse HEAD)" ]

printf 'ok: firn-sync-local-inputs\n'
