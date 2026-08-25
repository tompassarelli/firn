#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'firn-views-native: cannot locate Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-views-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'firn-views-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'firn-views-native: %s\n' "$*" >&2
  exit 1
}

for command in bash bun cmp diff find git rg timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

json="$beagle/native-core/src/native/json.bjs"
schema_path="$beagle/native-core/src/beagle/nix_schema_path.bjs"
core="$repo/native/firn_views.bjs"
pure="$repo/native/firn_views_test.bjs"
native="$repo/native/firn_views_native.bjs"
bridge="$repo/native/firn_views_host.mjs"

printf 'firn-views-js: building one closed typed family graph\n' >&2
mkdir -p "$scratch/build"
timeout --foreground 240 "$beagle/bin/beagle" build \
  "$json" "$schema_path" "$core" "$pure" "$native" --out "$scratch/build" \
  >"$scratch/build.out" 2>"$scratch/build.err" || {
    sed -n '1,260p' "$scratch/build.err" >&2
    die 'closed Beagle/JS family build failed'
  }
pure_js="$(find "$scratch/build" -name views-test.js -print -quit)"
native_js="$(find "$scratch/build" -name views-native.js -print -quit)"
[[ -n "$pure_js" && -f "$pure_js" ]] || die 'pure views module was not emitted'
[[ -n "$native_js" && -f "$native_js" ]] || die 'views host module was not emitted'

cat >"$scratch/firn-views-native" <<EOF
#!/usr/bin/env bash
exec env FIRN_VIEWS_MODULE='$native_js' bun '$bridge' "\$@"
EOF
chmod +x "$scratch/firn-views-native"

printf 'firn-views-native: pure fixed JSON/source/fake-result cases\n' >&2
FIRN_VIEWS_TEST_MODULE="$pure_js" \
timeout --foreground 30 bun --eval \
  'const m = await import(process.env.FIRN_VIEWS_TEST_MODULE); process.exitCode = m.run([]);' \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die 'pure fixture executable failed'
[[ "$(rg -c '^PASS ' "$scratch/pure.out")" == '10' ]] \
  || die 'pure fixture count changed'
[[ ! -s "$scratch/pure.err" ]] || die 'pure fixtures wrote stderr'

fixture="$scratch/repo"
fakebin="$scratch/fake-bin"
mkdir -p \
  "$fixture/.beagle-cache" \
  "$fixture/scripts" \
  "$fixture/modules/both" \
  "$fixture/modules/linux" \
  "$fixture/modules/darwin" \
  "$fixture/modules/neither" \
  "$fixture/hosts/fixture-host" \
  "$fakebin"

cat >"$fixture/flake.lock" <<'EOF'
{"root":"root","nodes":{"root":{"inputs":{"alpha":"alpha","broken":"broken"}},"alpha":{"inputs":{"nixpkgs":["nixpkgs"]},"original":{"type":"github","owner":"a","repo":"alpha"},"locked":{"lastModified":1,"rev":"aaaaaaaa1111"}},"broken":{"original":{"type":"path","path":"/tmp/broken"},"locked":{"rev":"bbbbbbbb2222"}}}}
EOF

cat >"$fixture/.beagle-cache/schema.json" <<'EOF'
[
  {"name":"services.shared.enable","t":"bool","declarations":["shared.nix"]},
  {"name":"services.linux.enable","t":"bool"},
  {"name":"services.mode","t":"nullOr","inner":{"t":"enum","enum":["a","b"]}},
  {"name":"users.users.<name>.shell","t":"path"},
  {"name":"programs.dynamic","t":"attrsOf","inner":{"t":"anything"}}
]
EOF

cat >"$fixture/.beagle-cache/schema-darwin.json" <<'EOF'
[
  {"name":"services.shared.enable","t":"bool"},
  {"name":"services.darwin.enable","t":"bool"},
  {"name":"users.users.<name>.shell","t":"path"},
  {"name":"programs.dynamic","t":"attrsOf"}
]
EOF

cat >"$fixture/.beagle-cache/schema-submodules.json" <<'EOF'
{"submodules":{"services.submodule":[{"p":"services.submodule.enable","t":"bool"}]}}
EOF

cat >"$fixture/modules/both/default.bnix" <<'EOF'
#lang beagle/nix
{:services.shared.enable true}
EOF
cat >"$fixture/modules/both/sibling.bnix" <<'EOF'
#lang beagle/nix
{:users.users.tom.shell pkg}
EOF
cat >"$fixture/modules/linux/default.bnix" <<'EOF'
#lang beagle/nix
{:services.linux.enable true}
EOF
cat >"$fixture/modules/darwin/default.bnix" <<'EOF'
#lang beagle/nix
{:services.darwin.enable true}
EOF
cat >"$fixture/modules/neither/default.bnix" <<'EOF'
#lang beagle/nix
{:boot.unknown.enable true}
EOF
cat >"$fixture/hosts/fixture-host/configuration.bnix" <<'EOF'
#lang beagle/nix
{:services.mode "a"}
EOF
cat >"$fixture/flake.bnix" <<'EOF'
#lang beagle/nix
{:inputs {}}
EOF

cat >"$fakebin/firn" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'firn\t<%s>\t<%s>\t<%s>\n' \
  "${1:-}" "${2:-}" "${3:-}" >>"${FIRN_FAKE_LOG:?}"
printf 'schema-made:%s\n' "${3:-}"
printf 'schema-note\n' >&2
exit "${FIRN_FAKE_SCHEMA_STATUS:-0}"
EOF

cat >"$fakebin/nixos-rebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'nixos-rebuild'
  for argument in "$@"; do
    printf '\t<%s>' "$argument"
  done
  printf '\n'
} >>"${FIRN_FAKE_LOG:?}"
printf '40 old\n41 current\n'
printf 'generation-note\n' >&2
exit "${FIRN_FAKE_GEN_STATUS:-0}"
EOF
chmod +x "$fakebin/firn" "$fakebin/nixos-rebuild"

last_status=0
run_cli() {
  local name="$1"
  shift
  set +e
  timeout --foreground 30 env \
    PATH="$fakebin:$PATH" \
    FIRN_REPO="$fixture" \
    FIRN_HOST=fixture-host \
    FIRN_FAKE_LOG="$scratch/fake.log" \
    "$@" >"$scratch/$name.out" 2>"$scratch/$name.err"
  last_status=$?
  set -e
  printf '%s\n' "$last_status" >"$scratch/$name.status"
}

expect_status() {
  local name="$1" expected="$2"
  [[ "$(<"$scratch/$name.status")" == "$expected" ]] \
    || die "$name returned $(<"$scratch/$name.status"), expected $expected"
}

expect_contains() {
  local path_to_check="$1" literal="$2" label="$3"
  rg -F "$literal" "$path_to_check" >/dev/null \
    || die "$label did not contain: $literal"
}

printf 'firn-views-native: controlled Bun CLI cases\n' >&2

run_cli flake "$scratch/firn-views-native" flake inputs all
expect_status flake 0
expect_contains "$scratch/flake.out" 'would break the build' 'flake output'
expect_contains "$scratch/flake.out" 'nixpkgs shares nixpkgs' 'flake follows'
[[ ! -s "$scratch/flake.err" ]] || die 'flake success wrote stderr'

run_cli platform-all "$scratch/firn-views-native" platform list all
expect_status platform-all 0
expect_contains "$scratch/platform-all.out" 'Platform compatibility matrix (4 modules)' \
  'platform matrix'
expect_contains "$scratch/platform-all.out" '  both' 'platform sibling source'
expect_contains "$scratch/platform-all.out" '  linux' 'platform linux verdict'
expect_contains "$scratch/platform-all.out" '  darwin' 'platform darwin verdict'
expect_contains "$scratch/platform-all.out" '  neither' 'platform no-data verdict'
[[ ! -s "$scratch/platform-all.err" ]] \
  || die 'platform list success wrote stderr'

run_cli platform-show "$scratch/firn-views-native" platform show linux
expect_status platform-show 0
expect_contains "$scratch/platform-show.out" 'verdict: linux-only' \
  'platform show verdict'
expect_contains "$scratch/platform-show.out" 'services.linux.enable' \
  'platform show blocker'

run_cli safelist "$scratch/firn-views-native" platform safelist all
expect_status safelist 0
expect_contains "$scratch/safelist.out" '"darwin"' 'darwin-only safelist'
expect_contains "$scratch/safelist.out" '"both"' 'both safelist'

run_cli explain "$scratch/firn-views-native" schema explain \
  'fixture:1: unknown option services.mode'
expect_status explain 0
expect_contains "$scratch/explain.out" 'type:  nullOr (enum)' \
  'schema nested type'
expect_contains "$scratch/explain.out" 'enum:  "a", "b"' 'schema enum'
expect_contains "$scratch/explain.out" 'hosts/fixture-host/configuration.bnix' \
  'semantic schema reference'

run_cli suggest "$scratch/firn-views-native" schema explain services.modf
expect_status suggest 1
expect_contains "$scratch/suggest.err" 'services.mode' 'schema suggestion'

: >"$scratch/fake.log"
run_cli extract "$scratch/firn-views-native" schema extract fixture-host
expect_status extract 0
printf '%s\n' \
  '>> firn schema extract fixture-host' \
  'schema-made:fixture-host' >"$scratch/extract.expected.out"
cmp -s "$scratch/extract.expected.out" "$scratch/extract.out" \
  || { diff -u "$scratch/extract.expected.out" "$scratch/extract.out" >&2 || true; \
       die 'schema extract stdout changed'; }
printf '%s\n' 'schema-note' >"$scratch/extract.expected.err"
cmp -s "$scratch/extract.expected.err" "$scratch/extract.err" \
  || die 'schema extract stderr changed'
printf '%s\n' 'firn	<schema>	<extract>	<fixture-host>' >"$scratch/extract.expected.log"
cmp -s "$scratch/extract.expected.log" "$scratch/fake.log" \
  || die 'schema extractor argv changed'

: >"$scratch/fake.log"
run_cli generation "$scratch/firn-views-native" host gen fixture-host
expect_status generation 0
printf '%s\n' 'current: 41' 'next:    42' \
  >"$scratch/generation.expected.out"
cmp -s "$scratch/generation.expected.out" "$scratch/generation.out" \
  || die 'generation output changed'
printf '%s\n' 'generation-note' >"$scratch/generation.expected.err"
cmp -s "$scratch/generation.expected.err" "$scratch/generation.err" \
  || die 'generation child stderr changed'
printf '%s\n' 'nixos-rebuild	<list-generations>' \
  >"$scratch/generation.expected.log"
cmp -s "$scratch/generation.expected.log" "$scratch/fake.log" \
  || die 'generation child argv changed'

set +e
timeout --foreground 30 env \
  PATH="$fakebin:$PATH" FIRN_REPO="$fixture" FIRN_HOST=fixture-host \
  FIRN_FAKE_LOG="$scratch/fake.log" FIRN_FAKE_GEN_STATUS=9 \
  "$scratch/firn-views-native" host gen fixture-host \
  >"$scratch/generation-red.out" 2>"$scratch/generation-red.err"
generation_red_status=$?
set -e
[[ "$generation_red_status" == '9' ]] \
  || die "generation failure returned $generation_red_status"
expect_contains "$scratch/generation-red.err" 'generation listing failed' \
  'generation failure'

run_cli invalid "$scratch/firn-views-native" platform stale
expect_status invalid 64
expect_contains "$scratch/invalid.err" 'Usage: firn flake inputs' 'usage error'

printf 'ok: Beagle/JS Firn views pass fixed JSON, source, and fake-child Bun gates\n'
