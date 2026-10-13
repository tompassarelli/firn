#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
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
core="$repo/native/firn_views.ts"
pure_js="$repo/native/firn_views_test.ts"
native_js="$repo/native/firn_views_native.ts"
bridge="$repo/native/firn_views_host.mjs"

printf 'firn-views-ts: running typed Bun family\n' >&2
cat >"$scratch/firn-views-native" <<EOF
#!/usr/bin/env bash
exec env FIRN_VIEWS_MODULE='$native_js' bun '$bridge' "\$@"
EOF
chmod +x "$scratch/firn-views-native"

FIRN_VIEWS_TEST_MODULE="$pure_js" \
timeout --foreground 30 bun --eval \
  'const m = await import(process.env.FIRN_VIEWS_TEST_MODULE); process.exitCode = m.runScenarios() + m.runProperties(process.env.CI ? 512 : 128);' \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die 'pure fixture executable failed'
[[ ! -s "$scratch/pure.err" ]] || die 'pure fixtures wrote stderr'

FIRN_VIEWS_CORE="$core" FIRN_REAL_LOCK="$repo/flake.lock" \
  timeout --foreground 30 bun - <<'JS'
import assert from 'node:assert/strict';
const p = await import(process.env.FIRN_VIEWS_CORE);
const text = await Bun.file(process.env.FIRN_REAL_LOCK).text();
const lock = JSON.parse(text);
const rows = p.flakeRows(text, 2000000000);
assert.equal(rows._tag, 'FlakeRows');
const inputs = lock.nodes[lock.root].inputs;
assert.deepEqual(rows.rows.map(row => row.name).sort(), Object.keys(inputs).sort());
for (const row of rows.rows) {
  const node = lock.nodes[inputs[row.name]];
  assert.equal(row.revision, node.locked?.rev?.slice(0,8) ?? '?');
  assert.equal(row.frozen, typeof node.original?.rev === 'string');
  assert.equal(row.broken, node.original?.type === 'path' && node.original.path.startsWith('/'));
  assert.equal(row.ageSeconds, node.locked?.lastModified === undefined ? -1 : 2000000000-node.locked.lastModified);
  assert.deepEqual(row.follows.map(follow => [follow.input,follow.target]).sort(),
    Object.entries(node.inputs ?? {}).filter(([,target]) => Array.isArray(target)).map(([name,target]) => [name,target.at(-1)]).sort());
}
const plain = p.renderFlakeRows(rows.rows,false);
const tty = p.renderFlakeRows(rows.rows,true);
assert.ok(!plain.includes('\u001b['));
assert.ok(tty.includes('\u001b['));
let seed = 73421;
const random = () => (seed = seed * 48271 % 2147483647);
for (let index=0; index<(process.env.CI ? 512 : 128); index++) {
  const modules = Array.from({length: 5}, (_, i) => `module${i}`);
  const linuxEverywhere = random()%2 === 0;
  const everywhere = linuxEverywhere ? modules.map(m => [m,'linux']) : [];
  const supported = ['darwin', ...(linuxEverywhere ? [] : ['linux'])]
    .flatMap(platform => modules.filter(() => random()%2 === 0).map(m => [m,platform]));
  const rows = [...everywhere, ...supported];
  const toRows = list => list.map(([m,platform]) => p.platformRow(m, platform));
  const matrix = p.platformMatrix(modules, rows.map(([m,platform]) => p.platformRow(m, platform)));
  const expected = modules.map(m => {
    const lacks = ['darwin','linux'].filter(platform => !rows.some(([n,q]) => n === m && q === platform));
    return {kind: lacks.length === 0 ? 'both' : lacks.length === 2 ? 'neither' : `${lacks[0] === 'darwin' ? 'linux' : 'darwin'}-only`, blockers: lacks};
  });
  assert.deepEqual(matrix.map(row => [String(row.verdict).replace(/^:/,'').replaceAll('_','-'),row.blockers]), expected.map(row => [row.kind,row.blockers]));
  const listed = p.renderPlatformList('all',matrix);
  assert.equal(listed.status, 0);
  assert.ok(!listed.stdout.includes('Sources:'));
  assert.deepEqual(listed.stdout.split('\n').filter(line => /^\s+module[0-9]+\s*$/.test(line)).map(line => line.trim()).sort(), modules);
  const darwinListed = p.renderPlatformList('darwin',matrix);
  assert.deepEqual(darwinListed.stdout.split('\n').filter(line => /^\s+module[0-9]+\s*$/.test(line)).map(line => line.trim()).sort(), rows.filter(([,q]) => q === 'darwin').map(([m]) => m).sort());
  const safelist = p.renderPlatformSafelist(toRows(everywhere), toRows(supported));
  assert.equal(safelist.status, 0);
  assert.equal(safelist.stdout, ['darwin','linux'].filter(platform => !(linuxEverywhere && platform === 'linux')).map(platform => {
    const names = supported.filter(([,q]) => q === platform).map(([m]) => m).sort();
    return names.length === 0 ? '' : `${names.length === 1 ? names[0] : `[${names.join(', ')}]`} supports ${platform}\n`;
  }).join(''));
  const shown = p.renderPlatformShow('module0', matrix);
  assert.equal(shown.status, 0);
  assert.equal(shown.stdout.split('unsupported on:\n')[1] ?? '', expected[0].blockers.map(platform => `  ${platform}\n`).join(''));
}
console.log('ok: recorded flake decoders and generated platform model');
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
mkdir -p "$fixture/.beagle-cache"
cp -- "$here/fixtures/beagle-bfe06d21f4bd-2026-10-11-openssh-schema.json" \
  "$fixture/.beagle-cache/schema.json"
set +e
timeout --foreground 60 env FIRN_REPO="$fixture" \
  "$scratch/firn-views-native" schema explain services.openssh.enable \
  >"$scratch/explain.out" 2>"$scratch/explain.err"
status=$?
set -e
[[ "$status" == 0 ]] || die "schema explain returned $status"
rg -qx 'path:  services.openssh.enable' "$scratch/explain.out" || die 'explain lacks the path'
rg -qx 'type:  bool' "$scratch/explain.out" || die 'explain lacks the type'
set +e
timeout --foreground 60 env FIRN_REPO="$fixture" \
  "$scratch/firn-views-native" schema explain 'error: unknown option services.openssh.enabl' \
  >"$scratch/misspelled.out" 2>"$scratch/misspelled.err"
status=$?
set -e
[[ "$status" == 1 ]] || die "misspelled explain returned $status"
rg -qx '  services.openssh.enable' "$scratch/misspelled.out" "$scratch/misspelled.err" \
  || die 'misspelled explain does not suggest services.openssh.enable'
printf 'ok: views recorded references, child conservation and generation boundary\n'
