#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/firn-schema-input-fingerprint"
EXTRACT="$SCRIPT_DIR/firn-extract-schema"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/firn-schema-fingerprint.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

write_lock() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'JSON'
{
  "root": "root",
  "nodes": {
    "root": {"inputs": {
      "nixpkgs": "nixpkgs-node",
      "home-manager": "home-manager-node",
      "nix-darwin": "darwin-node",
      "north": "north-node"
    }},
    "nixpkgs-node": {"locked": {"narHash": "sha256-nixpkgs-1", "rev": "nixpkgs-1"}},
    "home-manager-node": {"locked": {"narHash": "sha256-hm-1", "rev": "hm-1"}},
    "darwin-node": {"locked": {"narHash": "sha256-darwin-1", "rev": "darwin-1"}},
    "north-node": {"locked": {"narHash": "sha256-north-1", "rev": "north-1"}}
  }
}
JSON
}

mutate_lock() {
  local path="$1" filter="$2" tmp
  tmp="$(mktemp "${path}.tmp.XXXXXX")"
  jq "$filter" "$path" >"$tmp"
  mv "$tmp" "$path"
}

LOCK="$SCRATCH/flake.lock"
write_lock "$LOCK"
nixos_initial="$($HELPER --mode nixos --lock "$LOCK")"
darwin_initial="$($HELPER --mode darwin --lock "$LOCK")"

mutate_lock "$LOCK" '.nodes["north-node"].locked.rev = "north-2"'
[[ "$($HELPER --mode nixos --lock "$LOCK")" == "$nixos_initial" ]]
[[ "$($HELPER --mode darwin --lock "$LOCK")" == "$darwin_initial" ]]

mutate_lock "$LOCK" '.nodes["nixpkgs-node"].locked.rev = "nixpkgs-2"'
nixos_after_nixpkgs="$($HELPER --mode nixos --lock "$LOCK")"
darwin_after_nixpkgs="$($HELPER --mode darwin --lock "$LOCK")"
[[ "$nixos_after_nixpkgs" != "$nixos_initial" ]]
[[ "$darwin_after_nixpkgs" != "$darwin_initial" ]]

mutate_lock "$LOCK" '.nodes["darwin-node"].locked.rev = "darwin-2"'
[[ "$($HELPER --mode nixos --lock "$LOCK")" == "$nixos_after_nixpkgs" ]]
[[ "$($HELPER --mode darwin --lock "$LOCK")" != "$darwin_after_nixpkgs" ]]

mutate_lock "$LOCK" 'del(.nodes.root.inputs["home-manager"])'
if "$HELPER" --mode nixos --lock "$LOCK" >/dev/null 2>&1; then
  echo 'FAIL: missing schema input was accepted' >&2
  exit 1
fi

# Integration: a successful extraction records the matching sidecar for each
# platform. The fake extractor keeps this test hermetic and fast.
REPO="$SCRATCH/repo"
BEAGLE="$SCRATCH/beagle"
mkdir -p "$REPO/scripts" "$BEAGLE/bin"
cp "$HELPER" "$REPO/scripts/firn-schema-input-fingerprint"
write_lock "$REPO/flake.lock"
cat >"$BEAGLE/bin/beagle-extract-schema" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$(dirname "$out")"
printf '[]\n' >"$out"
SH
chmod +x "$BEAGLE/bin/beagle-extract-schema"

FIRN_REPO="$REPO" BEAGLE_PATH="$BEAGLE" "$EXTRACT"
[[ -s "$REPO/.beagle-cache/schema.json" ]]
[[ "$(<"$REPO/.beagle-cache/schema.inputs.sha256")" == \
   "$($HELPER --mode nixos --lock "$REPO/flake.lock")" ]]

FIRN_REPO="$REPO" BEAGLE_PATH="$BEAGLE" "$EXTRACT" --darwin
[[ -s "$REPO/.beagle-cache/schema-darwin.json" ]]
[[ "$(<"$REPO/.beagle-cache/schema-darwin.inputs.sha256")" == \
   "$($HELPER --mode darwin --lock "$REPO/flake.lock")" ]]

printf 'ok: schema fingerprints ignore unrelated inputs and split Darwin dependencies\n'
