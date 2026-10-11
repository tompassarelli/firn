#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export XDG_CACHE_HOME=$scratch/cache
nixpkgs=$(jq -r '.nodes[.nodes[.root].inputs.nixpkgs].locked |
  "github:\(.owner)/\(.repo)/\(.rev)"' "$repo/flake.lock")
cd "$scratch"
git init -q
git config user.name 'Firn check'
git config user.email 'check@example.invalid'
cat > flake.nix <<SOURCE
{
  inputs.nixpkgs.url = "$nixpkgs";
  outputs = { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      host = name: {
        inherit pkgs;
        config.system.build.toplevel = pkgs.writeText name (builtins.readFile (./. + ("/" + name)));
      };
    in {
      nixosConfigurations = { alpha = host "alpha"; beta = host "beta"; };
      darwinConfigurations.mac = {
        inherit pkgs;
        system = pkgs.writeText "mac" (builtins.readFile ./mac);
      };
    };
}
SOURCE
printf 'first\n' > alpha
printf 'stable\n' > beta
printf 'stable\n' > mac
git add -- flake.nix alpha beta mac
nix flake lock --offline
git add -- flake.nix flake.lock alpha beta mac
git commit -qm baseline
export SAFE_PUSH_LAND_BASE SAFE_PUSH_LAND_HEAD
SAFE_PUSH_LAND_BASE=$(git rev-parse HEAD)
printf 'second %s\n' "${scratch##*/}" > alpha
git add -- alpha
git commit -qm 'one host change'
SAFE_PUSH_LAND_HEAD=$(git rev-parse HEAD)
start=$SECONDS
bash "$repo/.github/scripts/host-diff.sh" build | tee changed.log
printf 'one-host wall seconds: %s\n' "$((SECONDS-start))"
rg -q 'evaluated 3 base and 3 head hosts; 1 changed, 2 reused' changed.log
drv=$(awk '/host check: changed / {print $NF}' changed.log)
nix-store --check-validity "$(nix-store --query --outputs "$drv")"
export SAFE_PUSH_LAND_BASE=$SAFE_PUSH_LAND_HEAD
mkdir docs
printf 'documentation\n' > docs/readme.md
git add -- docs/readme.md
git commit -qm 'docs change'
SAFE_PUSH_LAND_HEAD=$(git rev-parse HEAD)
start=$SECONDS
bash "$repo/.github/scripts/host-diff.sh" build | tee docs.log
printf 'docs-only wall seconds: %s\n' "$((SECONDS-start))"
rg -q 'host check: skipped; no changed path' docs.log
printf '{ outputs = _: throw "injected evaluation fault"; }\n' > flake.nix
git add -- flake.nix
git commit -qm 'injected evaluation fault'
SAFE_PUSH_LAND_HEAD=$(git rev-parse HEAD)
if bash "$repo/.github/scripts/host-diff.sh" build >fault.log 2>&1; then
  printf 'host diff accepted an evaluation fault\n' >&2
  exit 1
fi
rg -q 'injected evaluation fault' fault.log
if rg -q 'host check: changed' fault.log; then
  printf 'host diff built before all evaluations passed\n' >&2
  exit 1
fi
printf 'ok: real Git/Nix host diff builds one changed derivation, reuses docs and rejects an evaluation fault\n'
