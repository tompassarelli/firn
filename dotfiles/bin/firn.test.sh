#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
source_repo="$(cd "$here/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-family-runtime-test.XXXXXX")"
cleanup() { rm -rf -- "${scratch:?}"; }
trap cleanup EXIT

home="$scratch/home"
beagle_path="$scratch/beagle-alt"
firn_repo="$scratch/firn-alt"
runtime_root="$scratch/runtime"
fake_bin="$scratch/bin"
mkdir -p "$home" "$beagle_path/bin" "$firn_repo/native" "$fake_bin"
cp -- "$source_repo"/native/*.bjs "$source_repo"/native/*.mjs \
  "$firn_repo/native/"
mkdir -p \
  "$beagle_path/native-core/src/beagle" \
  "$beagle_path/native-core/src/native" \
  "$beagle_path/store/src/store" \
  "$beagle_path/beagle-lib/lib/beagle"
for source in \
  "$beagle_path/native-core/src/beagle/datum_reader.bjs" \
  "$beagle_path/native-core/src/beagle/nix_schema_path.bjs" \
  "$beagle_path/native-core/src/native/json.bjs"; do
  printf '#lang beagle/js\n' >"$source"
done
for source in \
  "$beagle_path/store/src/store/slots.bgl" \
  "$beagle_path/store/src/store/types.bgl"; do
  printf '#lang beagle\n' >"$source"
done
printf 'export const fixture = true;\n' \
  >"$beagle_path/beagle-lib/lib/beagle/core.js"
printf 'export const fixtureHost = true;\n' \
  >"$beagle_path/beagle-lib/lib/beagle/host.js"

cat >"$beagle_path/bin/beagle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >>"$FAKE_BEAGLE_LOG"
[[ "${1:-}" == build ]] || exit 97
output="$3"
mkdir -p "$(dirname "$output")"
cat >"$output" <<'JS'
export function run(bridge, args) {
  const argv = Array.isArray(args) ? args : [];
  const family = argv[0] === 'repo' && argv[1] === 'validate'
    ? 'firn-schema' : 'firn-tag';
  return bridge.executeRuntime(family, argv);
}
JS
EOF
chmod +x "$beagle_path/bin/beagle"

cat >"$beagle_path/bin/beagle-build-all" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BUILD_ALL\0' >>"$FAKE_BEAGLE_LOG"
printf '%s\0' "$@" >>"$FAKE_BEAGLE_LOG"
out=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$out" ]]
mkdir -p "$out/firn" "$out/activity"
write_module() {
  local path="$1" label="$2"
  cat >"$path" <<JS
export function run() {
  process.stdout.write('prepared:alpha:$label\\n');
  return 0;
}
JS
}
write_module "$out/firn/tag-family.js" tag
write_module "$out/firn/flake-input-family.js" flake-input
write_module "$out/firn/inventory-family.js" inventory
write_module "$out/firn/authoring-native.js" authoring
write_module "$out/firn/views-native.js" views
write_module "$out/firn/repo-build-family.js" repo-build
write_module "$out/firn/schema-transaction-native.js" schema
write_module "$out/firn/repo-workflows-runtime.js" repo-workflow
write_module "$out/firn/rebuild-family.js" rebuild
write_module "$out/firn/prewarm.js" prewarm
write_module "$out/firn/system-policy-native.js" system-policy
write_module "$out/activity/menu.js" activity-menu
EOF
chmod +x "$beagle_path/bin/beagle-build-all"

cat >"$fake_bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
[[ "\${1:-}" == -C && "\${3:-}" == rev-parse && "\${4:-}" == HEAD ]]
case "\$2" in
  "$firn_repo") printf '1111111111111111111111111111111111111111\\n' ;;
  "$beagle_path") printf '2222222222222222222222222222222222222222\\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/git"

export HOME="$home"
export PATH="$fake_bin:$PATH"
export BEAGLE_PATH="$beagle_path"
export FIRN_REPO="$firn_repo"
export FIRN_RUNTIME_ROOT="$runtime_root"
export FAKE_BEAGLE_LOG="$scratch/beagle.log"

"$here/firn-runtime-update" >"$scratch/update.out"
target="$(readlink "$runtime_root/current")"
destination="$runtime_root/$target"
grep -Fxq 'format=firn-cli-runtime/v3' "$destination/manifest"
grep -Fxq 'scope=full' "$destination/manifest"
grep -Fxq 'firn_revision=1111111111111111111111111111111111111111' \
  "$destination/manifest"
grep -Fxq 'beagle_revision=2222222222222222222222222222222222222222' \
  "$destination/manifest"
for component in tag flake-input inventory authoring views repo-build schema \
  repo-workflow rebuild prewarm; do
  grep -Fq "component=$component " "$destination/manifest"
done
for binary in firn-tag firn-flake-input firn-inventory firn-authoring \
  firn-views firn-repo-build firn-schema firn-repo-workflow firn-rebuild \
  firn-prewarm; do
  [[ -x "$destination/bin/$binary" ]]
done
[[ "$("$here/firn" repo validate)" == prepared:alpha:schema ]]

"$here/firn-runtime-update" >"$scratch/update-again.out"
[[ "$(readlink "$runtime_root/current")" == "$target" ]]
! tr '\0' '\n' <"$FAKE_BEAGLE_LOG" | grep -Fxq native-exe

[[ "$("$here/_firn-live-tool" activity-menu)" == \
  prepared:alpha:activity-menu ]]
[[ "$(printf '{}\n' | "$here/_firn-live-tool" firn-system-policy)" == \
  prepared:alpha:system-policy ]]

missing_root="$scratch/missing-runtime"
set +e
FIRN_RUNTIME_ROOT="$missing_root" "$here/firn" repo validate \
  >"$scratch/missing.out" 2>"$scratch/missing.err"
status=$?
set -e
[[ "$status" -eq 127 ]]
grep -Fxq 'firn: user runtime is not installed; run firn-runtime-update' \
  "$scratch/missing.err"
[[ ! -s "$scratch/missing.out" ]]

printf 'firn-family-runtime: PASS\n'
