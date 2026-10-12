#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-$repo}/firn-review-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir -p "$scratch/repo" "$scratch/bin" "$scratch/tmp"
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
given {node: Node} holds
Goal is a Node
Goal holds
requirements
  Goal holds
GAL
git -C "$scratch/repo" init -q
git -C "$scratch/repo" add main.gal
git -C "$scratch/repo" -c user.name=Firn -c user.email=firn@example.invalid commit -qm baseline
git -C "$scratch/repo" tag gen-41
cat >"$scratch/bin/readlink" <<'SH'
#!/usr/bin/env bash
printf 'system-41-link\n'
SH
chmod +x "$scratch/bin/readlink"
galileo="${FIRN_GALILEO:-$HOME/.local/lib/firn/cli/current/bin/galileo}"
run_review() {
  env PATH="$scratch/bin:$PATH" TMPDIR="$scratch/tmp" FIRN_REPO="$scratch/repo" \
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
printf 'ok: dry-run prints both host consequences, rejects introduced failure, and retires snapshots\n'
