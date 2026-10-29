#!/usr/bin/env bash
set -euo pipefail
declare -A revisions=([base]=${SAFE_PUSH_LAND_BASE:?} [head]=${SAFE_PUSH_LAND_HEAD:?})
action=${1:-build}
case "$action" in select|build) ;; *) printf 'usage: host-diff.sh [select|build]\n' >&2; exit 64 ;; esac
reaching=$(git diff --name-only --no-renames "${revisions[base]}" "${revisions[head]}" |
  grep -Ev '^docs/|\.test\.(sh|py)$' || true)
if [ -z "$reaching" ]; then
  printf 'host check: skipped; no changed path outside docs/ and tests reaches a host\n'
  exit 0
fi
build_host=${FIRN_BUILD_HOST:-$(hostname -s)}
cache=${XDG_CACHE_HOME:-$HOME/.cache}/firn/host-drvs
mkdir -p "$cache"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
nix_version=$(nix --version | tr -c 'A-Za-z0-9.\n' '_')
evaluate() {
  local revision=$1 tree entry
  tree=$(git rev-parse "${revisions[$revision]}^{tree}")
  entry="$cache/$tree-$nix_version.json"
  if [ "$revision" = base ] && [ -s "$entry" ]; then
    cp -- "$entry" "$scratch/$revision.json"
    printf 'host check: %s drvPaths reused from cache for tree %s\n' "$revision" "$tree"
    return
  fi
  mkdir -p "$scratch/$revision/source"
  git archive "${revisions[$revision]}" | tar -x -C "$scratch/$revision/source"
  # Path snapshots omit Git revision metadata from the system identity.
  nix eval --json --impure --expr "
    let
      flake = builtins.getFlake \"path:$scratch/$revision/source\";
    in {
      nixosConfigurations = builtins.mapAttrs
        (_: host: host.config.system.build.toplevel.drvPath) (flake.nixosConfigurations or {});
      darwinConfigurations = builtins.mapAttrs
        (_: host: host.system.drvPath) (flake.darwinConfigurations or {});
    }
  " > "$scratch/$revision.json"
  cp -- "$scratch/$revision.json" "$entry.$$"
  mv -- "$entry.$$" "$entry"
}
evaluate base > "$scratch/base.log" 2>&1 &
base_job=$!
status=0
evaluate head || status=$?
wait "$base_job" || status=$?
cat "$scratch/base.log"
[ "$status" = 0 ] || exit "$status"
jq -r --slurp '
  .[0] as $base | .[1] as $head |
  $head | to_entries[] | .key as $kind | .value | to_entries[] |
  [$kind, .key, .value,
    (if $base[$kind][.key] == .value then "reused" else "changed" end)] | @tsv
' "$scratch/base.json" "$scratch/head.json" > "$scratch/hosts.tsv"
jq -r --slurp '
  .[0] as $base | .[1] as $head |
  $base | to_entries[] | .key as $kind | .value | keys[] as $host |
  select($head[$kind][$host] == null) | "host check: removed \($kind).\($host)"
' "$scratch/base.json" "$scratch/head.json"
changed=0
reused=0
while IFS=$'\t' read -r kind host drv status; do
  printf 'host check: %s %s.%s %s\n' "$status" "$kind" "$host" "$drv"
  if [ "$status" = reused ]; then
    reused=$((reused + 1))
  else
    changed=$((changed + 1))
    if [ "$action" = build ]; then
      if [ "$kind" = nixosConfigurations ] && [ "$host" = "$build_host" ]; then
        nix build --no-link "${drv}^*"
      else
        printf 'host check: evaluated only %s.%s; its closure is built when landing from %s\n' "$kind" "$host" "$host"
      fi
    fi
  fi
done < "$scratch/hosts.tsv"
printf 'host check: evaluated %s base and %s head hosts; %s changed, %s reused\n' \
  "$(jq '[.[] | length] | add' "$scratch/base.json")" \
  "$(jq '[.[] | length] | add' "$scratch/head.json")" "$changed" "$reused"
