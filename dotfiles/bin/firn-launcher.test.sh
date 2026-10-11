#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-launcher-test.XXXXXX")"
cleanup() { rm -rf -- "${scratch:?}"; }
trap cleanup EXIT
mkdir -p "$scratch/runtime/current/bin" "$scratch/unrelated"
: >"$scratch/runtime/current/bin/firn-host.mjs"
cat >"$scratch/runtime/current/bin/bun" <<'RUNNER'
#!/usr/bin/env bash
printf '%s\n' "$FIRN_REPO"
RUNNER
chmod +x "$scratch/runtime/current/bin/bun"
cp "$repo/config/galileo-revision" "$scratch/runtime/current/galileo-revision"
export HOME="$scratch/home"
for checkout in migrated unmigrated explicit home/code/nixos-config/main; do
  mkdir -p "$scratch/$checkout/config"
  cp "$repo/config/galileo-revision" "$scratch/$checkout/config/galileo-revision"
  git init -q "$scratch/$checkout"
done
: >"$scratch/migrated/flake.gal"
: >"$scratch/unmigrated/flake.bnix"
export FIRN_RUNTIME_ROOT="$scratch/runtime"
unset FIRN_REPO FIRN_BUN
cd "$repo/modules/codex"
[[ "$("$here/firn" repo diff all)" == "$repo" ]]
[[ "$(FIRN_REPO="$scratch/explicit" "$here/firn" repo diff all)" == "$scratch/explicit" ]]
cd "$scratch/migrated"
[[ "$("$here/firn" repo diff all)" == "$scratch/migrated" ]]
cd "$scratch/unmigrated"
[[ "$("$here/firn" repo diff all)" == "$HOME/code/nixos-config/main" ]] # hardcoded-repo-path:allow
cd "$scratch/unrelated"
[[ "$("$here/firn" repo diff all)" == "$HOME/code/nixos-config/main" ]] # hardcoded-repo-path:allow
printf 'ok: Firn uses the current migrated checkout (flake.gal), explicit override, or main outside a migrated checkout\n'
