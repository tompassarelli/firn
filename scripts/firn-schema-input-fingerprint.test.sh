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
mkdir -p "$REPO/scripts" "$REPO/config" "$BEAGLE/bin"
cp "$HELPER" "$REPO/scripts/firn-schema-input-fingerprint"
printf '%s\n' '{"freeformKeyPrefixes":[],"typesNeedingDefault":["lib/types.bool"]}' \
  >"$REPO/config/beagle-validate.json"
write_lock "$REPO/flake.lock"
cat >"$BEAGLE/bin/beagle-extract-schema" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=''
hm=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --hm) hm=1; shift ;;
    *) shift ;;
  esac
done
if [[ "$hm" -eq 1 && "${FAIL_HM:-0}" -eq 1 ]]; then
  exit 23
fi
mkdir -p "$(dirname "$out")"
if [[ "$hm" -eq 1 ]]; then
  printf '%s\n' '[{"name":"home.stateVersion","t":"str"}]' >"$out"
else
  printf '%s\n' '[{"name":"services.openssh.enable","t":"bool"}]' >"$out"
fi
SH
chmod +x "$BEAGLE/bin/beagle-extract-schema"

FIRN_REPO="$REPO" BEAGLE_PATH="$BEAGLE" "$EXTRACT"
[[ -s "$REPO/.beagle-cache/schema.json" ]]
[[ -s "$REPO/.beagle-cache/schema-hm.json" ]]
cmp -s "$REPO/config/beagle-validate.json" \
  "$REPO/.beagle-cache/validate-config.json"
[[ "$(<"$REPO/.beagle-cache/schema.inputs.sha256")" == \
   "$($HELPER --mode nixos --lock "$REPO/flake.lock")" ]]

# A failed second-stage HM extraction cannot publish a partial generation.
before_schema="$(sha256sum "$REPO/.beagle-cache/schema.json")"
before_hm="$(sha256sum "$REPO/.beagle-cache/schema-hm.json")"
before_fp="$(sha256sum "$REPO/.beagle-cache/schema.inputs.sha256")"
if FIRN_REPO="$REPO" BEAGLE_PATH="$BEAGLE" FAIL_HM=1 "$EXTRACT" >/dev/null 2>&1; then
  echo 'FAIL: failed HM extraction reported success' >&2
  exit 1
fi
[[ "$(sha256sum "$REPO/.beagle-cache/schema.json")" == "$before_schema" ]]
[[ "$(sha256sum "$REPO/.beagle-cache/schema-hm.json")" == "$before_hm" ]]
[[ "$(sha256sum "$REPO/.beagle-cache/schema.inputs.sha256")" == "$before_fp" ]]

FIRN_REPO="$REPO" BEAGLE_PATH="$BEAGLE" "$EXTRACT" --darwin
[[ -s "$REPO/.beagle-cache/schema-darwin.json" ]]
[[ "$(<"$REPO/.beagle-cache/schema-darwin.inputs.sha256")" == \
   "$($HELPER --mode darwin --lock "$REPO/flake.lock")" ]]

printf 'ok: schema fingerprints split dependencies and extraction publishes complete atomic generations\n'
