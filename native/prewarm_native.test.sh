#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH/bin/beagle"
else
  git_common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)"
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main/bin/beagle"
fi
bun="${BUN:-$(command -v bun || true)}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-prewarm-js.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'prewarm-js: retained failure artifacts at %s\n' "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

[[ -x "$beagle" ]] || { printf 'prewarm-js: missing Beagle: %s\n' "$beagle" >&2; exit 1; }
[[ -x "$bun" ]] || { printf 'prewarm-js: missing Bun; set BUN\n' >&2; exit 1; }

timeout --foreground 30 "$beagle" build \
  "$repo/native/prewarm.bjs" "$scratch/firn-prewarm.js"

POLICY="$scratch/firn-prewarm.js" "$bun" --eval '
  const p = await import(process.env.POLICY);
  const same = p["container-main-candidates"](
    "/srv/firn/worktrees/prewarm", "/srv/firn/main/.git");
  if (JSON.stringify(same) !== JSON.stringify([
    "/srv/firn/main", "/srv/firn/worktrees/prewarm"])) process.exit(1);
  if (p["warm-key"]("/srv/firn/main", "abc", "main", "whiterabbit", "linux")
      !== "git+file:///srv/firn/main?rev=abc&ref=main#nixosConfigurations.whiterabbit.config.system.build.toplevel") process.exit(1);
  if (p["hook-argv-or-empty"]("prepared", [], "/bin/firn", "/srv/firn/main", "key").length !== 0) process.exit(1);
'

container="$scratch/container"
main="$container/main"
lane="$container/worktrees/slug"
runtime="$scratch/runtime"
host="$(hostname)"
mkdir -p "$main/native" "$main/hosts/$host" "$container/worktrees" "$runtime"
printf '#lang beagle/js\n(ns firn.main)\n' >"$main/native/firn.bjs"
printf '#lang beagle/nix\n(ns flake)\n' >"$main/flake.bnix"
printf 'fixture\n' >"$main/hosts/$host/marker"
git init -q -b main "$main"
git -C "$main" add -- native/firn.bjs flake.bnix "hosts/$host/marker"
git -C "$main" -c user.name=prewarm-test \
  -c user.email=prewarm-test@example.invalid commit -qm base
git -C "$main" worktree add -q -b slug "$lane"

head_sha="$(git -C "$main" rev-parse HEAD)"
case "$(uname -s)" in
  Darwin) attr="darwinConfigurations.$host.system" ;;
  *) attr="nixosConfigurations.$host.config.system.build.toplevel" ;;
esac
expected_key="git+file://$main?rev=$head_sha&ref=main#$attr"
actual_key="$(
  FIRN_REPO="$lane" XDG_RUNTIME_DIR="$runtime" \
  FIRN_PREWARM_MODULE="$scratch/firn-prewarm.js" \
  timeout --foreground 30 "$bun" "$repo/native/prewarm_host.mjs" --print-warm-key
)"
[[ "$actual_key" == "$expected_key" ]]

FIRN_REPO="$lane" XDG_RUNTIME_DIR="$runtime" \
FIRN_PREWARM_MODULE="$scratch/firn-prewarm.js" \
  timeout --foreground 30 "$bun" "$repo/native/prewarm_host.mjs" \
    --plan-detached "$repo/native/prewarm_host.mjs" >"$scratch/detached.plan"
grep -Fxq -- '--worker' "$scratch/detached.plan"
grep -Fxq -- "$expected_key" "$scratch/detached.plan"
[[ ! -e "$runtime/firn-prewarm.lease" ]]

printf 'ok: Beagle/JS Firn prewarm policy and Bun plan adapter pass\n'
