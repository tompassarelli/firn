#!/usr/bin/env bash
# Hermetic controls for clean-worktree schema bootstrap and validation truth.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${BEAGLE_PATH:-}" ]; then
  for _bp in "$HOME/code/beagle/main" "$HOME/code/beagle" "$REPO/../beagle"; do
    if [ -x "$_bp/bin/beagle-validate" ]; then BEAGLE_PATH="$_bp"; break; fi
  done
  unset _bp
fi
BEAGLE_PATH="${BEAGLE_PATH:-$(cd "$REPO/.." && pwd)/beagle}"
FIRN_VALIDATE="$REPO/scripts/firn-validate"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/firn-validate-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT

SEED="$SCRATCH/seed"
mkdir -p "$SEED"
printf '%s\n' \
  '[{"name":"services.openssh.enable","t":"bool"},{"name":"boot.loader.systemd-boot.enable","t":"bool"},{"inner":{"t":"submodule"},"name":"environment.etc","t":"attrsOf"}]' \
  >"$SEED/schema.json"
printf '%s\n' \
  '[{"name":"home.stateVersion","t":"str"}]' \
  >"$SEED/schema-hm.json"

FAKE_EXTRACT="$SCRATCH/firn-extract-schema"
cat >"$FAKE_EXTRACT" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
repo=${FIRN_REPO:?}
seed=${FIRN_SCHEMA_TEST_SEED:?}
counter=${FIRN_SCHEMA_TEST_COUNTER:?}
cache=$repo/.beagle-cache
mkdir -p "$cache"
cp "$seed/schema.json" "$cache/schema.json.next"
cp "$seed/schema-hm.json" "$cache/schema-hm.json.next"
cp "$repo/config/beagle-validate.json" "$cache/validate-config.json.next"
"$repo/scripts/firn-schema-input-fingerprint" --mode nixos --lock "$repo/flake.lock" \
  --beagle-path "$BEAGLE_PATH" \
  >"$cache/schema.inputs.sha256.next"
mv "$cache/schema.json.next" "$cache/schema.json"
mv "$cache/schema-hm.json.next" "$cache/schema-hm.json"
mv "$cache/validate-config.json.next" "$cache/validate-config.json"
mv "$cache/schema.inputs.sha256.next" "$cache/schema.inputs.sha256"
printf 'extract\n' >>"$counter"
SH
chmod +x "$FAKE_EXTRACT"

seed_scratch() {
  local dir=$1
  mkdir -p "$dir/scripts" "$dir/config"
  cp "$REPO/flake.lock" "$dir/flake.lock"
  cp "$REPO/scripts/firn-schema-input-fingerprint" "$dir/scripts/firn-schema-input-fingerprint"
  cp "$REPO/scripts/firn-lint-nix" "$dir/scripts/firn-lint-nix"
  cp "$REPO/config/beagle-validate.json" "$dir/config/beagle-validate.json"
}

write_clean_module() {
  local dir=$1
  cat >"$dir/clean.bnix" <<'EOF'
#lang beagle/nix
(ns modules.clean-schema-bootstrap-test)

(nix/module (config lib pkgs)
  {:options.myConfig.modules.clean-schema-bootstrap-test.enable
     (lib/mkEnableOption "clean schema bootstrap control")
   :config
     (lib/mkIf config.myConfig.modules.clean-schema-bootstrap-test.enable
       {:services.openssh.enable true})})
EOF
}

run_validate() {
  local dir=$1
  FIRN_REPO="$dir" \
  BEAGLE_PATH="$BEAGLE_PATH" \
  FIRN_EXTRACT_SCHEMA="$FAKE_EXTRACT" \
  FIRN_SCHEMA_TEST_SEED="$SEED" \
  FIRN_SCHEMA_TEST_COUNTER="$dir/extract.count" \
    "$FIRN_VALIDATE" 2>&1
}

seed_current_cache() {
  local dir=$1
  FIRN_REPO="$dir" \
  BEAGLE_PATH="$BEAGLE_PATH" \
  FIRN_SCHEMA_TEST_SEED="$SEED" \
  FIRN_SCHEMA_TEST_COUNTER="$dir/extract.count" \
    "$FAKE_EXTRACT"
  : >"$dir/extract.count"
}

# A truly clean worktree bootstraps once, validates, and reuses the exact cache.
CLEAN_DIR="$SCRATCH/clean"
seed_scratch "$CLEAN_DIR"
write_clean_module "$CLEAN_DIR"
run_validate "$CLEAN_DIR" >/dev/null
[[ $(wc -l <"$CLEAN_DIR/extract.count") -eq 1 ]]
[[ -s "$CLEAN_DIR/.beagle-cache/schema.json" ]]
[[ -s "$CLEAN_DIR/.beagle-cache/schema-hm.json" ]]
cmp -s "$CLEAN_DIR/config/beagle-validate.json" \
  "$CLEAN_DIR/.beagle-cache/validate-config.json"
run_validate "$CLEAN_DIR" >/dev/null
[[ $(wc -l <"$CLEAN_DIR/extract.count") -eq 1 ]]

# Missing, stale, partial, and policy-drifted cache components regenerate.
for fault in stale-fingerprint missing-hm partial-json policy-drift; do
  dir="$SCRATCH/$fault"
  seed_scratch "$dir"
  write_clean_module "$dir"
  seed_current_cache "$dir"
  case "$fault" in
    stale-fingerprint) printf 'stale\n' >"$dir/.beagle-cache/schema.inputs.sha256" ;;
    missing-hm) unlink "$dir/.beagle-cache/schema-hm.json" ;;
    partial-json) printf '[{"name":' >"$dir/.beagle-cache/schema.json" ;;
    policy-drift) printf '{}\n' >"$dir/.beagle-cache/validate-config.json" ;;
  esac
  run_validate "$dir" >/dev/null
  [[ $(wc -l <"$dir/extract.count") -eq 1 ]]
  python3 - "$dir/.beagle-cache/schema.json" "$dir/.beagle-cache/schema-hm.json" <<'PY'
import json, pathlib, sys
for value in (json.loads(pathlib.Path(p).read_text()) for p in sys.argv[1:]):
    assert isinstance(value, list) and value
PY
done

# A planted unknown still fails after automatic bootstrap with a pointed path.
UNKNOWN_DIR="$SCRATCH/unknown"
seed_scratch "$UNKNOWN_DIR"
cat >"$UNKNOWN_DIR/planted.bnix" <<'EOF'
#lang beagle/nix
(ns modules.planted-unknown-test)

(nix/module (config lib pkgs)
  {:options.myConfig.modules.planted-unknown-test.enable
     (lib/mkEnableOption "planted unknown option control")
   :config
     (lib/mkIf config.myConfig.modules.planted-unknown-test.enable
       {:boot.totallyFakeUnknownOptionXYZ.enable true})})
EOF
out="$(run_validate "$UNKNOWN_DIR")" && rc=0 || rc=$?
[[ "$rc" -ne 0 ]]
grep -q 'planted.bnix:[0-9]*:[0-9]*: unknown NixOS option: boot.totallyFakeUnknownOptionXYZ.enable' <<<"$out"

# The tracked freeform policy remains narrow, not a namespace-wide suppression.
FREEFORM_DIR="$SCRATCH/freeform"
seed_scratch "$FREEFORM_DIR"
cat >"$FREEFORM_DIR/freeform.bnix" <<'EOF'
#lang beagle/nix
(ns modules.freeform-classified-test)

(nix/module (config lib pkgs)
  {:options.myConfig.modules.freeform-classified-test.enable
     (lib/mkEnableOption "classified freeform prefix")
   :config
     (lib/mkIf config.myConfig.modules.freeform-classified-test.enable
       {:environment.etc.random-generated-file.text "hello"})})
EOF
run_validate "$FREEFORM_DIR" >/dev/null
cat >"$FREEFORM_DIR/nonfreeform.bnix" <<'EOF'
#lang beagle/nix
(ns modules.non-freeform-unknown-test)

(nix/module (config lib pkgs)
  {:options.myConfig.modules.non-freeform-unknown-test.enable
     (lib/mkEnableOption "unknown outside classified freeform prefix")
   :config
     (lib/mkIf config.myConfig.modules.non-freeform-unknown-test.enable
       {:environment.totallyNotARealTopLevelOption.enable true})})
EOF
out="$(run_validate "$FREEFORM_DIR")" && rc=0 || rc=$?
[[ "$rc" -ne 0 ]]
grep -q 'unknown NixOS option: environment.totallyNotARealTopLevelOption.enable' <<<"$out"

printf 'ok: clean-worktree schema bootstrap is exact, deterministic, self-healing, and validation remains strict\n'
