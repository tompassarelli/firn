#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-$repo}/firn-review-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT
passed=0
mkdir -p "$scratch/repo/config" "$scratch/bin" "$scratch/tmp" "$scratch/runtime/versions/current/bin"
cp "$repo/config/galileo-revision" "$scratch/repo/config/galileo-revision"
cp "$repo/config/galileo-revision" "$scratch/runtime/versions/current/galileo-revision"
cat >"$scratch/repo/main.gal" <<'GAL'
use firn/tags

firefox is a Module
browsers is a Tag
firefox is tagged browsers
browsers sets myConfig.modules.firefox.default to true for firefox
whiterabbit is a Host
whiterabbit runs linux
whiterabbit enables browsers
nexus is a Host
nexus runs linux
nexus enables browsers
linux is a Platform
linux allows every module

type Node
given Node holds
Goal is a Node
Goal holds
requirements
  Goal holds
GAL
git -C "$scratch/repo" init -q
git -C "$scratch/repo" add main.gal config/galileo-revision
git -C "$scratch/repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm baseline
git -C "$scratch/repo" tag gen-41
cat >"$scratch/bin/readlink" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == /nix/var/nix/profiles/system ]]; then
  printf 'system-41-link\n'
else
  exec /run/current-system/sw/bin/readlink "$@"
fi
SH
chmod +x "$scratch/bin/readlink"
galileo="${FIRN_GALILEO:-$HOME/.local/lib/firn/cli/current/bin/galileo}"
ln -s "$galileo" "$scratch/runtime/versions/current/bin/galileo"
review_repo="$scratch/repo"
run_review() {
  env PATH="$scratch/bin:$PATH" TMPDIR="$scratch/tmp" FIRN_REPO="$review_repo" FIRN_RUNTIME_ROOT="$scratch/runtime" \
    FIRN_GALILEO="$galileo" FIRN_REBUILD_MODULE="$scratch/must-not-load.js" \
    bun "$here/firn_rebuild_host.mjs" host rebuild --dry-run >"$scratch/$1.out" 2>&1
}
sed -i '/browsers sets/d' "$scratch/repo/main.gal"
git -C "$scratch/repo" add main.gal
git -C "$scratch/repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm consequence
run_review holds || { cat "$scratch/holds.out" >&2; exit 1; }
grep -Fq 'whiterabbit:' "$scratch/holds.out"
grep -Fq 'nexus:' "$scratch/holds.out"
sed -i '/^Goal holds$/d' "$scratch/repo/main.gal"
git -C "$scratch/repo" add main.gal
git -C "$scratch/repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm failure
sed -i '/^Goal is a Node$/a Goal holds' "$scratch/repo/main.gal"
if run_review fails; then
  printf 'review accepted an introduced failure\n' >&2
  exit 1
fi
grep -Fq 'reject' "$scratch/fails.out"
git -C "$scratch/repo" tag -d gen-41 >/dev/null
if run_review missing; then
  printf 'review accepted an unavailable last switched revision\n' >&2
  exit 1
fi
grep -Fq 'last switched revision is unavailable' "$scratch/missing.out"
[[ "$(git -C "$scratch/repo" worktree list --porcelain | rg -c '^worktree ')" == 1 ]]
[[ -z "$(ls -A "$scratch/tmp")" ]]
passed=$((passed + 1))
printf 'ok: dry-run prints both host consequences, rejects introduced failure, and retires snapshots\n'
old_pin=8daa31d83df6688b0346d1692e56372226611a26
current_pin="$(cat "$repo/config/galileo-revision")"
old_galileo=
for version in "${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/versions/"*; do
  if [[ -f "$version/galileo-revision" && "$(cat "$version/galileo-revision")" == "$old_pin" && -x "$version/bin/galileo" ]]; then
    old_galileo="$version/bin/galileo"
    break
  fi
done
[[ -n "$old_galileo" ]] || { printf 'missing recorded scenario Galileo %s\n' "$old_pin" >&2; exit 1; }
review_repo="$scratch/segments"
mkdir -p "$review_repo/config" "$review_repo/dotfiles/bin" "$scratch/runtime/versions/old/bin"
cp "$repo/dotfiles/bin/firn-runtime-update" "$review_repo/dotfiles/bin/firn-runtime-update"
printf '%s\n' "$old_pin" >"$review_repo/config/galileo-revision"
printf '%s\n' "$old_pin" >"$scratch/runtime/versions/old/galileo-revision"
cat >"$review_repo/main.gal" <<'GAL'
given flake input {name: Text} follows {input: Text} from {target: Text}
flake input "nixpkgs" follows "nixpkgs" from "test"
GAL
git -C "$review_repo" init -q
git -C "$review_repo" add main.gal config/galileo-revision dotfiles/bin/firn-runtime-update
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm 'recorded braced slots'
git -C "$review_repo" tag gen-41
segment_base="$(git -C "$review_repo" rev-parse HEAD)"
printf 'flake input "firn" follows "firn" from "test"\n' >>"$review_repo/main.gal"
sed -i 's/{name: Text}/?name: Text/; s/{input: Text}/?input: Text/; s/{target: Text}/?target: Text/' "$review_repo/main.gal"
git -C "$review_repo" add main.gal
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm 'old pin segment'
segment_boundary="$(git -C "$review_repo" rev-parse HEAD)"
printf '%s\n' "$current_pin" >"$review_repo/config/galileo-revision"
git -C "$review_repo" add main.gal config/galileo-revision
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm 'new pin after slot conversion'
printf 'flake input "galileo" follows "galileo" from "test"\n' >>"$review_repo/main.gal"
git -C "$review_repo" add main.gal
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm 'current pin segment'
segment_head="$(git -C "$review_repo" rev-parse HEAD)"
rm -- "$scratch/runtime/versions/current/bin/galileo"
cat >"$scratch/runtime/versions/old/bin/galileo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s %s\n' "$(cat config/galileo-revision)" "$(git rev-parse HEAD)" "$3" >>"$FIRN_FIXTURE_CALLS"
if [[ "${FIRN_FIXTURE_OLD_STATUS:-0}" != 0 ]]; then exit "$FIRN_FIXTURE_OLD_STATUS"; fi
exec "$FIRN_FIXTURE_OLD_BINARY" "$@"
SH
cat >"$scratch/runtime/versions/current/bin/galileo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s %s\n' "$(cat config/galileo-revision)" "$(git rev-parse HEAD)" "$3" >>"$FIRN_FIXTURE_CALLS"
if [[ "${FIRN_FIXTURE_STATUS:-0}" != 0 ]]; then exit "$FIRN_FIXTURE_STATUS"; fi
exec "$FIRN_FIXTURE_CURRENT_BINARY" "$@"
SH
chmod +x "$scratch/runtime/versions/"{old,current}/bin/galileo
export FIRN_FIXTURE_CALLS="$scratch/segments.calls" FIRN_FIXTURE_OLD_BINARY="$old_galileo" FIRN_FIXTURE_CURRENT_BINARY="$galileo"
run_review segments || { cat "$scratch/segments.out" >&2; exit 1; }
printf '%s %s %s\n' "$old_pin" "$segment_boundary" "$segment_base" "$current_pin" "$segment_head" "$segment_boundary" >"$scratch/segments.expected"
cmp "$scratch/segments.expected" "$FIRN_FIXTURE_CALLS"
[[ "$(rg -c '^verdict: approve$' "$scratch/segments.out")" == 2 ]]
for segment_status in 2 7; do
  export FIRN_FIXTURE_STATUS="$segment_status"
  : >"$FIRN_FIXTURE_CALLS"
  if run_review "segment-$segment_status"; then status=0; else status=$?; fi
  [[ "$status" == "$segment_status" ]]
  cmp "$scratch/segments.expected" "$FIRN_FIXTURE_CALLS"
done
unset FIRN_FIXTURE_STATUS
printf '%s %s %s\n' "$old_pin" "$segment_boundary" "$segment_base" >"$scratch/old.expected"
export FIRN_FIXTURE_OLD_STATUS=2
: >"$FIRN_FIXTURE_CALLS"
if run_review first-unknown; then status=0; else status=$?; fi
[[ "$status" == 2 ]]
cmp "$scratch/old.expected" "$FIRN_FIXTURE_CALLS"
unset FIRN_FIXTURE_OLD_STATUS
cat >"$scratch/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'materialize\n' >>"$FIRN_FIXTURE_BUILDS"
if [[ "${FIRN_FIXTURE_BUILD_STATUS:-0}" != 0 ]]; then exit "$FIRN_FIXTURE_BUILD_STATUS"; fi
while [[ "$1" != --target-dir ]]; do shift; done
mkdir -p "$2/release"
cp "$FIRN_FIXTURE_CURRENT_BINARY" "$2/release/galileo"
SH
chmod +x "$scratch/bin/nix"
export FIRN_FIXTURE_BUILDS="$scratch/builds"
: >"$FIRN_FIXTURE_BUILDS"
run_review cached || { cat "$scratch/cached.out" >&2; exit 1; }
[[ ! -s "$FIRN_FIXTURE_BUILDS" ]]
mv "$scratch/runtime/versions/current/bin/galileo" "$scratch/current-galileo"
: >"$FIRN_FIXTURE_CALLS"
export FIRN_FIXTURE_BUILD_STATUS=7
if run_review materialization-failure; then status=0; else status=$?; fi
[[ "$status" == 7 ]]
cmp "$scratch/old.expected" "$FIRN_FIXTURE_CALLS"
[[ "$(wc -l <"$FIRN_FIXTURE_BUILDS")" == 1 ]]
unset FIRN_FIXTURE_BUILD_STATUS
: >"$FIRN_FIXTURE_CALLS"
run_review uncached || { cat "$scratch/uncached.out" >&2; exit 1; }
grep -Fq 'firn Galileo materialized:' "$scratch/uncached.out"
[[ "$(rg -c '^verdict: approve$' "$scratch/uncached.out")" == 2 ]]
[[ "$(wc -l <"$FIRN_FIXTURE_BUILDS")" == 2 ]]
cmp "$scratch/old.expected" "$FIRN_FIXTURE_CALLS"
[[ ! -e "$scratch/runtime/current" ]]
for version in "$scratch/runtime/versions/"*; do
  if [[ "$version" != "$scratch/runtime/versions/current" && "$version" != "$scratch/runtime/versions/old" ]]; then
    rm -rf -- "$version"
  fi
done
mv "$scratch/current-galileo" "$scratch/runtime/versions/current/bin/galileo"
git -C "$review_repo" checkout -qb side-pin
printf '%s\n' "$old_pin" >"$review_repo/config/galileo-revision"
git -C "$review_repo" add config/galileo-revision
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm 'side branch pin'
git -C "$review_repo" checkout -q -
printf 'flake input "side" follows "side" from "test"\n' >>"$review_repo/main.gal"
git -C "$review_repo" add main.gal
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm 'main branch progresses'
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid merge -q -s ours side-pin -m 'retain main pin'
segment_head="$(git -C "$review_repo" rev-parse HEAD)"
printf '%s %s %s\n' "$old_pin" "$segment_boundary" "$segment_base" "$current_pin" "$segment_head" "$segment_boundary" >"$scratch/segments.expected"
: >"$FIRN_FIXTURE_CALLS"
run_review first-parent || { cat "$scratch/first-parent.out" >&2; exit 1; }
cmp "$scratch/segments.expected" "$FIRN_FIXTURE_CALLS"
git -C "$review_repo" rm -q config/galileo-revision
git -C "$review_repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm 'missing pin'
missing_end="$(git -C "$review_repo" rev-parse HEAD)"
if run_review missing-pin; then status=0; else status=$?; fi
[[ "$status" == 2 ]]
grep -Fxq "firn rebuild: $missing_end has no config/galileo-revision; review cannot approve" "$scratch/missing-pin.out"
[[ "$(git -C "$review_repo" worktree list --porcelain | rg -c '^worktree ')" == 1 ]]
[[ -z "$(ls -A "$scratch/tmp")" ]]
passed=$((passed + 1))
printf 'ok: recorded two-pin syntax journey selects each segment snapshot, propagates exits 2 and 7, materializes uncached pins, rejects build failure and missing pin, and follows first-parent boundaries\n'
printf 'tests: %s passed, 0 failed\n' "$passed"
