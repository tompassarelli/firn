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
run_review() {
  env PATH="$scratch/bin:$PATH" TMPDIR="$scratch/tmp" FIRN_REPO="$scratch/repo" \
    FIRN_REBUILD_MODULE="$scratch/must-not-load.js" \
    bun "$here/firn_rebuild_host.mjs" host rebuild --dry-run >"$scratch/$1.out" 2>&1
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
if run_review fails; then
  printf 'review accepted a committed assertion failure masked by a dirty edit\n' >&2
  exit 1
fi
rg -Fq 'assertion' "$scratch/fails.out"
git -C "$scratch/repo" tag -d gen-41 >/dev/null
if run_review missing; then
  printf 'review accepted an unavailable last switched revision\n' >&2
  exit 1
fi
rg -Fq 'last switched revision is unavailable' "$scratch/missing.out"
[[ "$(git -C "$scratch/repo" worktree list --porcelain | rg -c '^worktree ')" == 1 ]]
[[ -z "$(ls -A "$scratch/tmp")" ]]
printf 'ok: Nix review validates committed snapshots, rejects assertion failures and missing revisions, and retires snapshots\n'
