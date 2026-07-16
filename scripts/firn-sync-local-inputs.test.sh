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

output="$($SCRIPT)"
grep -q 'already current' <<<"$output"

# Tool/editor state is not part of a Git input snapshot and must not block.
printf 'local state\n' >"$TMP/beagle/untracked"
output="$($SCRIPT)"
grep -q 'already current' <<<"$output"

printf 'v2\n' >>"$TMP/north/source"
git -C "$TMP/north" add source
git -C "$TMP/north" commit -qm update
before_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
output="$($SCRIPT)"
after_count="$(git -C "$TMP/firn" rev-list --count HEAD)"
[ "$after_count" -eq $((before_count + 1)) ]
grep -q 'north.*→' <<<"$output"
[ "$(jq -r '.nodes.north.locked.rev' "$TMP/firn/flake.lock")" = "$(git -C "$TMP/north" rev-parse HEAD)" ]

printf 'dirty\n' >>"$TMP/fram/source"
if "$SCRIPT" >"$TMP/out" 2>"$TMP/err"; then
  echo 'expected dirty local repo rejection' >&2
  exit 1
fi
grep -q 'uncommitted tracked changes' "$TMP/err"

printf 'ok: firn-sync-local-inputs\n'
