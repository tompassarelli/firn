#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-stale-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir -p "$scratch/bin" "$scratch/tmp"
git init -q --bare -b main "$scratch/origin.git"
git clone -q "$scratch/origin.git" "$scratch/repo" 2>/dev/null
git -C "$scratch/repo" config user.name Firn
git -C "$scratch/repo" config user.email firn@example.invalid
git -C "$scratch/repo" commit -qm baseline --allow-empty
git -C "$scratch/repo" push -q origin HEAD:main
git clone -q "$scratch/origin.git" "$scratch/peer" 2>/dev/null
git -C "$scratch/peer" config user.name Firn
git -C "$scratch/peer" config user.email firn@example.invalid
cat >"$scratch/bin/readlink" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == /nix/var/nix/profiles/system ]]; then
  printf 'system-41-link\n'
else
  exec /run/current-system/sw/bin/readlink "$@"
fi
SH
chmod +x "$scratch/bin/readlink"
dry_run() {
  env PATH="$scratch/bin:$PATH" TMPDIR="$scratch/tmp" FIRN_REPO="$scratch/repo" FIRN_HOST=fixture \
    FIRN_SYSTEM_PROFILE="$scratch/no-profile" FIRN_SYSTEM_FLAKE="$scratch/no-system" \
    FIRN_REBUILD_MODULE="$scratch/must-not-load.js" \
    bun "$here/firn_rebuild_host.mjs" host rebuild --dry-run >"$scratch/out" 2>&1
}
expect() {
  local want="$1" label="$2" status=0
  dry_run || status=$?
  [[ "$status" == "$want" ]] || { cat "$scratch/out" >&2; printf '%s exited %s, not %s\n' "$label" "$status" "$want" >&2; exit 1; }
}
proceeds() {
  expect 65 "$1"
  rg -Fq 'last switched revision is unavailable' "$scratch/out"
}
proceeds 'HEAD equal to origin/main'
git -C "$scratch/peer" commit -qm landed --allow-empty
git -C "$scratch/peer" push -q origin HEAD:main
landed="$(git -C "$scratch/peer" rev-parse HEAD)"
expect 64 'HEAD behind origin/main'
rg -Fq "firn rebuild --landed $landed" "$scratch/out"
[[ "$(git -C "$scratch/repo" rev-parse origin/main)" == "$landed" ]]
git -C "$scratch/repo" merge -q --ff-only origin/main
git -C "$scratch/repo" commit -qm lane --allow-empty
proceeds 'HEAD ahead of origin/main'
git -C "$scratch/repo" reset -q --hard HEAD~2
git -C "$scratch/repo" commit -qm diverged --allow-empty
proceeds 'HEAD diverged from origin/main'
git -C "$scratch/repo" reset -q --hard HEAD~1
git -C "$scratch/repo" remote set-url origin "$scratch/gone.git"
expect 64 'HEAD behind a last fetched origin/main with a failed fetch'
rg -Fq 'last fetched origin/main (fetch failed)' "$scratch/out"
rg -Fq "firn rebuild --landed $landed" "$scratch/out"
printf 'ok: firn rebuild --dry-run refuses a checkout behind origin/main and names firn rebuild --landed; equal, ahead and diverged HEADs proceed\n'
