#!/usr/bin/env bash
set -euo pipefail

check="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/firn-check"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-check-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT

root="$scratch/checkout"
mkdir -p "$root" "$scratch/bin"
for tool in statix deadnix firn-tools; do
  printf '#!/usr/bin/env bash\n' >"$scratch/bin/$tool"
done
cat >"$scratch/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NIX_CALLS"
if [[ "$*" == "eval --raw --impure --expr builtins.currentSystem" ]]; then
  printf 'x86_64-linux'
fi
EOF
chmod +x "$scratch/bin/"*

export NIX_CALLS="$scratch/calls"
PATH="$scratch/bin:$PATH" FIRN_REPO="$root" bash "$check" >/dev/null

while IFS= read -r call; do
  [[ "$call" == "eval --raw --impure --expr builtins.currentSystem" ]] && continue
  if [[ "$call" != *"path:$root"* ]]; then
    printf 'firn-check.test: nix %s reads the flake from the working directory as git+file, which libgit2 refuses in the root-owned firn-landed-rebuild snapshot (north#699)\n' "$call" >&2
    exit 1
  fi
done <"$NIX_CALLS"
printf 'firn-check.test: every nix call reads path:%s\n' "$root"
