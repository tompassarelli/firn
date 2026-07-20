#!/usr/bin/env bash
# firn-validate.test.sh — hermetic controls for firn-validate's schema-cache
# truthfulness and unknown-option enforcement.
#
# Runs the REAL scripts/firn-validate + real ../beagle/bin/beagle-validate
# against a scratch repo seeded with THIS repo's real schema cache
# (.beagle-cache/schema.json, schema-hm.json, validate-config.json) and
# flake.lock, so the schema content and fingerprint math are authentic —
# only the .bnix sources under test are synthetic.
#
# Covers the three done_when controls for schema-cache truthfulness:
#   1. planted unknown option -> nonzero exit, pointed file:line:col diagnostic
#   2. stale/wrong schema-cache fingerprint -> nonzero exit, pointed diagnostic
#   3. an explicitly classified freeform prefix stays permissive (narrow rule),
#      while an unrelated unknown option in the SAME top-level namespace still
#      fails -- proving the rule is classified, not a blanket suppression.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BEAGLE_PATH="${BEAGLE_PATH:-$(cd "$REPO/.." && pwd)/beagle}"
FIRN_VALIDATE="$REPO/scripts/firn-validate"

if [[ ! -f "$REPO/.beagle-cache/schema.json" ]]; then
  echo "firn-validate.test.sh: $REPO/.beagle-cache/schema.json missing — run ./scripts/firn-extract-schema first" >&2
  exit 2
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/firn-validate-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

seed_scratch() {
  local dir="$1"
  mkdir -p "$dir/.beagle-cache" "$dir/scripts"
  cp "$REPO/.beagle-cache/schema.json" "$dir/.beagle-cache/schema.json"
  cp "$REPO/.beagle-cache/schema-hm.json" "$dir/.beagle-cache/schema-hm.json"
  [[ -f "$REPO/.beagle-cache/validate-config.json" ]] &&
    cp "$REPO/.beagle-cache/validate-config.json" "$dir/.beagle-cache/validate-config.json"
  cp "$REPO/.beagle-cache/schema.inputs.sha256" "$dir/.beagle-cache/schema.inputs.sha256"
  cp "$REPO/flake.lock" "$dir/flake.lock"
  cp "$REPO/scripts/firn-schema-input-fingerprint" "$dir/scripts/firn-schema-input-fingerprint"
  cp "$REPO/scripts/firn-lint-nix" "$dir/scripts/firn-lint-nix"
}

run_validate() {
  # Usage: run_validate <scratch-dir> ; prints combined output, returns exit code
  local dir="$1"
  FIRN_REPO="$dir" BEAGLE_PATH="$BEAGLE_PATH" "$FIRN_VALIDATE" 2>&1
}

# ---------------------------------------------------------------------------
# Control 1: planted unknown option must fail nonzero with a pointed
# file:line:col diagnostic naming the exact bogus option path.
# ---------------------------------------------------------------------------
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
       {
        :boot.totallyFakeUnknownOptionXYZ.enable true})})
EOF

out="$(run_validate "$UNKNOWN_DIR")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: planted unknown option was accepted (exit 0)" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "planted.bnix:[0-9]*:[0-9]*: unknown NixOS option: boot.totallyFakeUnknownOptionXYZ.enable" <<<"$out"; then
  echo "FAIL: planted unknown option did not produce a pointed file:line:col diagnostic" >&2
  echo "$out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Control 2: a schema cache whose recorded input fingerprint no longer
# matches flake.lock must fail nonzero with a pointed diagnostic, even
# though the .bnix sources themselves are clean.
# ---------------------------------------------------------------------------
STALE_DIR="$SCRATCH/stale"
seed_scratch "$STALE_DIR"
cat >"$STALE_DIR/clean.bnix" <<'EOF'
#lang beagle/nix
(ns modules.stale-cache-test)

(nix/module (config lib pkgs)
  {:options.myConfig.modules.stale-cache-test.enable
     (lib/mkEnableOption "stale-cache control (option itself is valid)")

   :config
     (lib/mkIf config.myConfig.modules.stale-cache-test.enable
       {
        :services.openssh.enable true})})
EOF
printf 'deadbeef-not-a-real-fingerprint\n' >"$STALE_DIR/.beagle-cache/schema.inputs.sha256"

out="$(run_validate "$STALE_DIR")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: stale schema-cache fingerprint was accepted (exit 0)" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "schema cache is stale" <<<"$out"; then
  echo "FAIL: stale schema-cache fingerprint did not produce a pointed diagnostic" >&2
  echo "$out" >&2
  exit 1
fi

# Missing fingerprint sidecar entirely must fail the same way (cache identity
# is unverifiable, not silently trusted).
MISSING_FP_DIR="$SCRATCH/missing-fp"
seed_scratch "$MISSING_FP_DIR"
cp "$STALE_DIR/clean.bnix" "$MISSING_FP_DIR/clean.bnix"
rm -f "$MISSING_FP_DIR/.beagle-cache/schema.inputs.sha256"

out="$(run_validate "$MISSING_FP_DIR")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: missing schema-cache fingerprint sidecar was accepted (exit 0)" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "no recorded input fingerprint" <<<"$out"; then
  echo "FAIL: missing schema-cache fingerprint sidecar did not produce a pointed diagnostic" >&2
  echo "$out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Control 3: an explicitly classified freeform prefix (environment.etc, from
# .beagle-cache/validate-config.json) stays permissive for an arbitrary leaf
# -- but an unrelated unknown option under the SAME top-level namespace
# ("environment") still fails. Proves the rule is a narrow classified
# allowance, not a blanket suppression of the whole namespace.
# ---------------------------------------------------------------------------
FREEFORM_DIR="$SCRATCH/freeform"
seed_scratch "$FREEFORM_DIR"
cat >"$FREEFORM_DIR/freeform.bnix" <<'EOF'
#lang beagle/nix
(ns modules.freeform-classified-test)

(nix/module (config lib pkgs)
  {:options.myConfig.modules.freeform-classified-test.enable
     (lib/mkEnableOption "classified freeform prefix stays narrow, not blanket")

   :config
     (lib/mkIf config.myConfig.modules.freeform-classified-test.enable
       {
        :environment.etc.myRandomPlantedFile.text "hello"})})
EOF
out="$(run_validate "$FREEFORM_DIR")" && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: a leaf under the classified freeform prefix environment.etc was rejected" >&2
  echo "$out" >&2
  exit 1
fi

cat >"$FREEFORM_DIR/nonfreeform.bnix" <<'EOF'
#lang beagle/nix
(ns modules.non-freeform-unknown-test)

(nix/module (config lib pkgs)
  {:options.myConfig.modules.non-freeform-unknown-test.enable
     (lib/mkEnableOption "unknown option outside the classified freeform prefix")

   :config
     (lib/mkIf config.myConfig.modules.non-freeform-unknown-test.enable
       {
        :environment.totallyNotARealTopLevelOption.enable true})})
EOF
out="$(run_validate "$FREEFORM_DIR")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: unknown option outside environment.etc was silently accepted (namespace-blanket suppression)" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "unknown NixOS option: environment.totallyNotARealTopLevelOption.enable" <<<"$out"; then
  echo "FAIL: unrelated environment.* unknown option did not produce a pointed diagnostic" >&2
  echo "$out" >&2
  exit 1
fi

printf 'ok: firn-validate planted-unknown, stale-cache, and classified-freeform controls\n'
