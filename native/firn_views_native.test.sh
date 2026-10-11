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
datum="$beagle/native-core/src/beagle/datum_reader.bjs"
schema_path="$beagle/native-core/src/beagle/nix_schema_path.bjs"
core="$repo/native/firn_views.bjs"
pure="$repo/native/firn_views_test.bjs"
native="$repo/native/firn_views_native.bjs"
bridge="$repo/native/firn_views_host.mjs"

printf 'firn-views-js: building one closed typed family graph\n' >&2
mkdir -p "$scratch/build"
timeout --foreground 240 "$beagle/bin/beagle-build-all" \
  "$json" "$datum" "$schema_path" "$core" "$pure" "$native" --out "$scratch/build" \
  >"$scratch/build.out" 2>"$scratch/build.err" || {
    sed -n '1,260p' "$scratch/build.err" >&2
    die 'closed Beagle/JS family build failed'
  }
pure_js="$(find "$scratch/build" -name views-test.js -print -quit)"
native_js="$(find "$scratch/build" -name views-native.js -print -quit)"
[[ -n "$native_js" && -f "$native_js" ]] || die 'views host module was not emitted'
mkdir -p "$scratch/build/node_modules/beagle"
cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
  "$scratch/build/node_modules/beagle/core.js"
printf '%s\n' '{"name":"beagle","type":"module"}' \
  >"$scratch/build/node_modules/beagle/package.json"

cat >"$scratch/firn-views-native" <<EOF
#!/usr/bin/env bash
exec env FIRN_VIEWS_MODULE='$native_js' bun '$bridge' "\$@"
EOF
chmod +x "$scratch/firn-views-native"

FIRN_VIEWS_TEST_MODULE="$pure_js" \
timeout --foreground 30 bun --eval \
  'const m = await import(process.env.FIRN_VIEWS_TEST_MODULE); process.exitCode = m["run-scenarios"]() + m["run-properties"](process.env.CI ? 512 : 128);' \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die 'pure fixture executable failed'
[[ ! -s "$scratch/pure.err" ]] || die 'pure fixtures wrote stderr'

FIRN_VIEWS_CORE="$scratch/build/firn/views.js" FIRN_REFERENCE_ROOT="$here/fixtures" FIRN_REAL_LOCK="$repo/flake.lock" \
  timeout --foreground 30 bun - <<'JS'
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const p = await import(process.env.FIRN_VIEWS_CORE);
const root = process.env.FIRN_REFERENCE_ROOT;
const schemaName = readdirSync(root).find(name => name.endsWith('-openssh-schema.json'));
const schemaText = await Bun.file(`${root}/${schemaName}`).text();
const schema = JSON.parse(schemaText);
const decoded = p['schema-from-json'](schemaText);
assert.equal(decoded._tag, 'SchemaLoaded');
assert.deepEqual(decoded.entries.map(row => [row.path,row.type,row.inner_type,row.enum_values]),
  schema.map(row => [row.name,row.t,row.inner?.t ?? '',row.enum ?? row.inner?.enum ?? []]));
const conflicting = {...schema[0], p:'different.path'};
assert.equal(p['schema-from-json'](JSON.stringify([conflicting]))._tag, 'SchemaRejected');
const subText = await Bun.file(`${root}/beagle-schema-submodules-2026-05-16-users.json`).text();
const sub = p['submodule-schema-from-json'](subText);
assert.equal(sub._tag, 'SchemaLoaded');
assert.deepEqual(sub.entries.map(row => row.path), JSON.parse(subText).submodules['users.users'].map(row => row.p ?? row.name));
const text = await Bun.file(process.env.FIRN_REAL_LOCK).text();
const lock = JSON.parse(text);
const rows = p['flake-rows'](text, 2000000000);
assert.equal(rows._tag, 'FlakeRows');
const inputs = lock.nodes[lock.root].inputs;
assert.deepEqual(rows.rows.map(row => row.name).sort(), Object.keys(inputs).sort());
for (const row of rows.rows) {
  const node = lock.nodes[inputs[row.name]];
  assert.equal(row.revision, node.locked?.rev?.slice(0,8) ?? '?');
  assert.equal(row.frozen, typeof node.original?.rev === 'string');
  assert.equal(row.broken, node.original?.type === 'path' && node.original.path.startsWith('/'));
  assert.equal(row.age_seconds, node.locked?.lastModified === undefined ? -1 : 2000000000-node.locked.lastModified);
  assert.deepEqual(row.follows.map(follow => [follow.input,follow.target]).sort(),
    Object.entries(node.inputs ?? {}).filter(([,target]) => Array.isArray(target)).map(([name,target]) => [name,target.at(-1)]).sort());
}
const plain = p['render-flake-rows'](rows.rows,false);
const tty = p['render-flake-rows'](rows.rows,true);
assert.ok(!plain.includes('\u001b['));
assert.ok(tty.includes('\u001b['));
const paths = await import(new URL('../beagle/nix-schema-path.js', pathToFileURL(process.env.FIRN_VIEWS_CORE)));
const referenceDocument = paths['->SourceDocument']('modules/reference/default.bnix', '#lang beagle/nix\n{:boot.initrd.systemd.root "fstab"}');
const explained = p['render-schema-explain']('boot.initrd.systemd.root', decoded.entries, [referenceDocument]);
assert.equal(explained.status, 0);
for (const value of ['nullOr','enum','fstab','gpt-auto',referenceDocument.source_id]) assert.ok(explained.stdout.includes(value), value);
const suggestion = p['render-schema-explain']('services.openssh.enabl', decoded.entries, []);
assert.equal(suggestion.status, 1);
assert.ok(suggestion.stderr.includes('services.openssh.enable'));
let seed = 73421;
const random = () => (seed = seed * 48271 % 2147483647);
const corpus = decoded.entries.filter(row => row.type === 'bool');
const subset = values => values.filter(() => random()%3 !== 0);
for (let index=0; index<(process.env.CI ? 512 : 128); index++) {
  const linux = subset(corpus), darwin = subset(corpus);
  const requested = Array.from({length: 5}, () => subset(corpus).map(row => row.path));
  const modules = requested.map((names,i) => p['->ModuleSource'](`module${i}`, [paths['->SourceDocument'](`modules/module${i}/default.bnix`, `#lang beagle/nix\n{${names.map(name => `:${name} true`).join(' ')}}`)]));
  const matrix = p['platform-matrix'](modules, linux, darwin);
  assert.equal(matrix._tag, 'PlatformLoaded');
  const expected = requested.map(names => {
    const linuxMissing = names.filter(name => !linux.some(row => row.path === name));
    const darwinMissing = names.filter(name => !darwin.some(row => row.path === name));
    return {kind: linuxMissing.length === 0 ? (darwinMissing.length === 0 ? 'both' : 'linux-only') : (darwinMissing.length === 0 ? 'darwin-only' : 'no-data'),
      blockers: [...new Set([...linuxMissing,...darwinMissing])].sort()};
  });
  assert.deepEqual(matrix.verdicts.map(row => [String(row.verdict).replace(/^:/,'').replaceAll('_','-'),row.blockers]), expected.map(row => [row.kind,row.blockers]));
  const listed = p['render-platform-list']('all',matrix.verdicts,linux.length,darwin.length);
  assert.equal(listed.status, 0);
  assert.deepEqual(listed.stdout.split('\n').filter(line => /^\s+module[0-9]+\s*$/.test(line)).map(line => line.trim()).sort(), modules.map(row => row.name).sort());
  const safelist = p['render-platform-safelist'](matrix.verdicts);
  assert.equal(safelist.status, 0);
  assert.deepEqual([...safelist.stdout.matchAll(/"(module[0-9]+)"/g)].map(match => match[1]).sort(), modules.filter((row,i) => ['both','darwin-only'].includes(expected[i].kind)).map(row => row.name).sort());
  const shown = p['render-platform-show']('module0', matrix.verdicts);
  assert.equal(shown.status, 0);
  for (const path of expected[0].blockers) assert.ok(shown.stdout.includes(path));
}
console.log('ok: recorded Beagle/flake decoders and generated platform model');
JS

fixture="$scratch/repo"
fakebin="$scratch/fake-bin"
mkdir -p "$fixture" "$fakebin"
cat >"$fakebin/nixos-rebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat "${FIRN_GENERATIONS_CAPTURE:?}"
printf 'generation-note\n' >&2
exit "${FIRN_FAKE_GEN_STATUS:-0}"
EOF
chmod +x "$fakebin/nixos-rebuild"
export FIRN_GENERATIONS_CAPTURE="$here/fixtures/nixos-rebuild-26.05-2026-10-11-generations.txt"
set +e
timeout --foreground 30 env PATH="$fakebin:$PATH" FIRN_REPO="$fixture" FIRN_HOST=fixture-host \
  "$scratch/firn-views-native" host gen fixture-host >"$scratch/generation.out" 2>"$scratch/generation.err"
status=$?
set -e
[[ "$status" == 0 ]] || die "generation boundary returned $status"
current=$(awk '$NF == "True" {print $1}' "$FIRN_GENERATIONS_CAPTURE")
awk '/^[^:]+:/ {print $2}' "$scratch/generation.out" >"$scratch/generation.values"
printf '%s\n' "$current" "$((current+1))" >"$scratch/generation.expected"
cmp "$scratch/generation.values" "$scratch/generation.expected" || die 'incorrect generation values'
set +e
timeout --foreground 30 env PATH="$fakebin:$PATH" FIRN_REPO="$fixture" FIRN_HOST=fixture-host FIRN_FAKE_GEN_STATUS=9 \
  "$scratch/firn-views-native" host gen fixture-host >"$scratch/failure.out" 2>"$scratch/failure.err"
status=$?
set -e
[[ "$status" == 9 ]] || die "child failure returned $status"
printf 'ok: views recorded references, child conservation and generation boundary\n'
