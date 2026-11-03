#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-review-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir -p "$scratch/repo/dotfiles/bin" "$scratch/bin" "$scratch/tmp"
cat >"$scratch/repo/flake.nix" <<'NIX'
{
  outputs = _: {
    lib.review = let policy = import ./policy.nix; in
      assert builtins.isBool policy.enabled;
      assert policy.enabled;
      "accepted";
  };
}
NIX
printf '{ enabled = true; }\n' >"$scratch/repo/policy.nix"
cat >"$scratch/repo/dotfiles/bin/firn-check" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
nix eval --json "$FIRN_REPO#lib.review"
SH
git -C "$scratch/repo" init -q
git -C "$scratch/repo" config user.name Firn
git -C "$scratch/repo" config user.email firn@example.invalid
git -C "$scratch/repo" add flake.nix policy.nix dotfiles/bin/firn-check
git -C "$scratch/repo" commit -qm baseline
git -C "$scratch/repo" tag gen-fixture-41
cat >"$scratch/bin/readlink" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == /nix/var/nix/profiles/system ]]; then
  printf 'system-41-link\n'
else
  exec /run/current-system/sw/bin/readlink "$@"
fi
SH
chmod +x "$scratch/bin/readlink"
run_review() {
  env PATH="$scratch/bin:$PATH" TMPDIR="$scratch/tmp" FIRN_REPO="$scratch/repo" FIRN_HOST=fixture \
    FIRN_SYSTEM_PROFILE="$scratch/profile" FIRN_SYSTEM_FLAKE="$scratch/system" \
    FIRN_REBUILD_MODULE="$scratch/must-not-load.js" \
    bun "$here/firn_rebuild_host.mjs" host rebuild --dry-run >"$scratch/$1.out" 2>&1
}
refuses() {
  if run_review "$1"; then printf 'review accepted %s\n' "$3" >&2; exit 1; fi
  rg -Fq "$2" "$scratch/$1.out"
}
printf '{ enabled = true; name = "changed"; }\n' >"$scratch/repo/policy.nix"
git -C "$scratch/repo" add policy.nix
git -C "$scratch/repo" commit -qm consequence
run_review holds || { cat "$scratch/holds.out" >&2; exit 1; }
rg -Fq 'with Nix evaluation' "$scratch/holds.out"
rg -Fq 'accepted' "$scratch/holds.out"
printf '{ enabled = false; }\n' >"$scratch/repo/policy.nix"
git -C "$scratch/repo" add policy.nix
git -C "$scratch/repo" commit -qm failure
printf '{ enabled = true; }\n' >"$scratch/repo/policy.nix"
refuses fails assertion 'a committed assertion failure masked by a dirty edit'
git -C "$scratch/repo" tag -d gen-fixture-41 >/dev/null
refuses missing 'last switched revision is unavailable' 'an unavailable last switched revision'
git -C "$scratch/repo" checkout -q -- policy.nix
git -C "$scratch/repo" revert --no-edit HEAD >/dev/null
mkdir -p "$scratch/profile/sw/bin"
switched_to() { printf '#!/bin/sh\necho %s\n' "$1" >"$scratch/profile/sw/bin/nixos-version"; chmod +x "$scratch/profile/sw/bin/nixos-version"; }
switched_to "$(git -C "$scratch/repo" rev-parse HEAD~2)"
run_review revision || { cat "$scratch/revision.out" >&2; exit 1; }
rg -Fq "reviewing $(git -C "$scratch/repo" rev-parse HEAD~2).." "$scratch/revision.out"
git -C "$scratch" init -q system
git -C "$scratch/system" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m upgrade
switched_to "$(git -C "$scratch/system" rev-parse HEAD)"
run_review system || { cat "$scratch/system.out" >&2; exit 1; }
rg -Fq "reviewing system flake $(git -C "$scratch/system" rev-parse HEAD).." "$scratch/system.out"
switched_to "$(printf 'e%.0s' {1..40})"
refuses unknown 'last switched revision is unavailable' 'a configuration revision no checkout holds'
[[ "$(git -C "$scratch/repo" worktree list --porcelain | rg -c '^worktree ')" == 1 ]]
[[ -z "$(ls -A "$scratch/tmp")" ]]
printf 'ok: Nix review validates committed snapshots, falls back to the switched configuration revision in firn or the system flake, rejects assertion failures and unknown revisions, and retires snapshots\n'
