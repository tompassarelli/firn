#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
bun="${FIRN_BUN:-${BUN:-$(command -v bun || true)}}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-prewarm-galileo.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'prewarm-galileo: retained failure artifacts at %s\n' "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

[[ -x "$bun" ]] || { printf 'prewarm-galileo: missing Bun; set FIRN_BUN\n' >&2; exit 1; }
runtime_root="${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/current"
export FIRN_GALILEO="${FIRN_GALILEO:-$runtime_root/bin/galileo}"
export FIRN_GALILEO_PREWARM="${FIRN_GALILEO_PREWARM:-$runtime_root/lib/firn/prewarm.gal}"
[[ -x "$FIRN_GALILEO" ]] || { printf 'prewarm-galileo: missing galileo; run firn-runtime-update or set FIRN_GALILEO\n' >&2; exit 1; }

source <(sed -n \
  -e '/^record_artifact() {/,/^}/p' \
  -e '/^record_generated_artifact() {/,/^}/p' \
  -e '/^materialize_js() {/,/^}/p' "$repo/dotfiles/bin/firn-runtime-update")
stage="$scratch/stage"
manifest="$stage/manifest"
declare -A artifact_ids=()
artifact_paths=()
binaries=()
mkdir -p "$stage/bin" "$stage/lib"
ln -s "$bun" "$stage/bin/bun"
materialize_js prewarm firn-prewarm prewarm.ts FIRN_PREWARM_MODULE \
  "$here/prewarm_host.mjs" "$here/prewarm.ts" "$FIRN_GALILEO_PREWARM"
rg -q '^component=prewarm module=lib/prewarm/prewarm.ts executable=bin/firn-prewarm runtime=bun$' "$manifest"
rg -q '^artifact=prewarm-source path=lib/prewarm/prewarm.ts ' "$manifest"

cmp "$FIRN_GALILEO_PREWARM" "$stage/lib/firn/prewarm.gal"
rg -q '^artifact=prewarm-policy path=lib/firn/prewarm.gal ' "$manifest"

export FIRN_GALILEO_REAL="$FIRN_GALILEO" FIRN_GALILEO_COUNT="$scratch/query.count"
cat >"$scratch/galileo-spy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'query\n' >>"$FIRN_GALILEO_COUNT"
exec "$FIRN_GALILEO_REAL" "$@"
SH
chmod +x "$scratch/galileo-spy"
export FIRN_GALILEO="$scratch/galileo-spy"
: >"$FIRN_GALILEO_COUNT"

POLICY="$stage/lib/prewarm/prewarm.ts" "$bun" - <<'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const p = await import(process.env.POLICY);
assert.equal(readFileSync(process.env.FIRN_GALILEO_COUNT, 'utf8'), '');
const same = p['container-main-candidates']('/srv/firn/worktrees/prewarm', '/srv/firn/main/.git');
assert.deepEqual(same, ['/srv/firn/main', '/srv/firn/worktrees/prewarm']);
assert.deepEqual(p['container-main-candidates']('/srv/firn/pins/rev', '/different/.git'),
  ['/srv/firn/main', '/different', '/srv/firn/pins/rev']);
assert.deepEqual(p['container-main-candidates']('/srv/firn/main', '/srv/firn/main/.git'), ['/srv/firn/main']);
assert.deepEqual(p['container-main-candidates']('/plain', {message:'unavailable'}), ['/plain']);
assert.deepEqual(p['container-main-candidates']('/pins/first/worktrees/second', '/not/a/common'),
  ['/pins/first/main', '/pins/first/worktrees/second']);
assert.equal(p['short-host']('whiterabbit.example.org'), 'whiterabbit');
assert.equal(p['short-host']('whiterabbit'), 'whiterabbit');
const snapshot = {repository:'/srv/firn/main', revision:'abc', branch:'main', host:'whiterabbit', platform:'linux'};
const uri = 'git+file:///srv/firn/main?rev=abc&ref=main';
const attribute = 'nixosConfigurations.whiterabbit.config.system.build.toplevel';
const key = `${uri}#${attribute}`;
assert.deepEqual(p['warm-spec'](snapshot), {uri, attribute, key});
assert.equal(p['warm-spec']({...snapshot, branch:'', platform:'darwin'}).key,
  'git+file:///srv/firn/main?rev=abc#darwinConfigurations.whiterabbit.system');
assert.deepEqual(p['command-argv'](''), []);
assert.deepEqual(p['command-argv']('firn\0\0host\0rebuild\0'), ['firn','','host','rebuild']);
const owner = {'worker-pid':101, 'child-pid':102, key};
assert.equal(p['render-owner'](owner), `101\n102\n${key}\n`);
assert.deepEqual(p['parse-lease-owner'](`101\n102\n${key}\n`), owner);
assert.deepEqual(p['parse-lease-owner'](` +101suffix\n102\n${key}`), owner);
for (const text of ['', `101\n102\n${key}\n\n`, `101\n\n${key}\n`, `0\n102\n${key}\n`, '101\n102\n\n']) {
  assert.ok('message' in p['parse-lease-owner'](text), JSON.stringify(text));
}
const executable = '/bin/firn';
const repository = snapshot.repository;
const worker = {pid:101, argv:[executable,'--worker',executable,repository,key]};
const child = {pid:102, argv:['nix','build','--no-link','--print-out-paths',key]};
assert.deepEqual(p['worker-argv'](executable,repository,key), worker.argv);
assert.deepEqual(p['nix-build-argv'](key), child.argv);
const supersede = (desired, current, w = worker, c = child) =>
  p['supersede-plan'](desired,current,executable,repository,owner,w,c);
assert.deepEqual(supersede(key,99), {deduplicated:key});
assert.deepEqual(supersede('next',99), {'child-pid':102,'worker-pid':101});
assert.deepEqual(supersede('next',101), {contended:key});
assert.deepEqual(supersede('next',99,{...worker,pid:103}), {contended:key});
assert.deepEqual(supersede('next',99,worker,{...child,argv:[...child.argv,'--extra']}), {contended:key});
assert.deepEqual(supersede(key,99,{...worker,argv:['unrelated']}), {contended:key});
assert.equal(p['stamp-current'](`${key}\r\n\r`,key),true);
assert.equal(p['stamp-current'](`${key} \n`,key),false);
assert.equal(p['stamp-current']('a\nb\r\n','a\nb'),true);
assert.deepEqual(p['stamp-plan'](key,0,false,100,100), {text:`${key}\n`});
for (const args of [[1,false,0,100],[0,true,0,100],[0,false,101,100]]) {
  assert.deepEqual(p['stamp-plan'](key,...args), {status:args[0]});
}
const detached = ['setsid','-f','nice','-n','19','ionice','-c','3',executable,'--worker',executable,repository,key];
assert.deepEqual(p['detached-worker-argv'](executable,repository,key), detached);
const hook = (state,lines) => p['hook-plan'](state,lines,executable,repository,key);
assert.deepEqual(hook('prepared',[]), {state:'prepared'});
assert.deepEqual(hook('committed',['malformed','abc def refs/heads/main']), {argv:detached});
for (const line of ['abc abc refs/heads/main','abc 000 refs/heads/main','abc def refs/heads/other','abc  def refs/heads/main','abc def refs/heads/main  ']) {
  assert.deepEqual(hook('committed',[line]), {state:'committed'}, line);
}
assert.deepEqual(hook('committed',['abc def refs/heads/main ']), {argv:detached});
assert.deepEqual(hook('prepared',['abc def refs/heads/main']), {state:'prepared'});
assert.deepEqual(hook('aborted',['abc def refs/heads/main']), {state:'aborted'});
for (const argv of [['firn','rebuild'],['/bin/bash','/bin/firn','host','rebuild','whiterabbit']]) {
  assert.equal(p['rebuild-argv'](argv),true);
}
for (const argv of [[],['firn','host'],['not-firn','rebuild'],['firn','repo','build']]) {
  assert.equal(p['rebuild-argv'](argv),false);
}
assert.equal(readFileSync(process.env.FIRN_GALILEO_COUNT, 'utf8'), 'query\n');
console.log('ok: checked Galileo prewarm policy, typed plans, parsing and identity guards');
console.log('ok: module import spawns 0 queries; cached policy scenarios spawn 1');
JS

container="$scratch/container"
main="$container/main"
lane="$container/worktrees/slug"
runtime="$scratch/runtime"
host="$(hostname)"
mkdir -p "$main/config" "$main/hosts/$host" "$container/worktrees" "$runtime"
printf 'fixture\n' >"$main/config/galileo-revision"
printf 'module flake\n' >"$main/flake.gal"
printf 'fixture\n' >"$main/hosts/$host/marker"
git init -q -b main "$main"
git -C "$main" add -- config/galileo-revision flake.gal "hosts/$host/marker"
git -C "$main" -c user.name=prewarm-test \
  -c user.email=prewarm-test@example.invalid commit -qm base
git -C "$main" worktree add -q -b slug "$lane"

head_sha="$(git -C "$main" rev-parse HEAD)"
case "$(uname -s)" in
  Darwin) attr="darwinConfigurations.$host.system" ;;
  *) attr="nixosConfigurations.$host.config.system.build.toplevel" ;;
esac
expected_key="git+file://$main?rev=$head_sha&ref=main#$attr"
export FIRN_REPO="$lane" XDG_RUNTIME_DIR="$runtime"
: >"$FIRN_GALILEO_COUNT"
actual_key="$(timeout --foreground 30 "$stage/bin/firn-prewarm" --print-warm-key)"
[[ "$actual_key" == "$expected_key" ]]
[[ "$(wc -l <"$FIRN_GALILEO_COUNT")" -eq 1 ]]
printf 'ok: --print-warm-key spawns 1 query\n'

unmigrated="$scratch/unmigrated"
mkdir -p "$unmigrated/config" "$unmigrated/hosts/$host"
cp "$main/config/galileo-revision" "$unmigrated/config/galileo-revision"
cp "$main/hosts/$host/marker" "$unmigrated/hosts/$host/marker"
printf '#lang beagle/nix\n(ns flake)\n' >"$unmigrated/flake.bnix"
git init -q -b main "$unmigrated"
git -C "$unmigrated" add -- config/galileo-revision flake.bnix "hosts/$host/marker"
git -C "$unmigrated" -c user.name=prewarm-test \
  -c user.email=prewarm-test@example.invalid commit -qm base
set +e
FIRN_REPO="$unmigrated" timeout --foreground 30 "$stage/bin/firn-prewarm" \
  --print-warm-key >"$scratch/unmigrated.out"
status=$?
set -e
[[ "$status" -eq 1 && ! -s "$scratch/unmigrated.out" ]]
printf 'ok: a checkout missing flake.gal is rejected\n'

timeout --foreground 30 "$stage/bin/firn-prewarm" \
  --plan-detached "$stage/bin/firn-prewarm" >"$scratch/detached.plan"
printf '%s\n' setsid -f nice -n 19 ionice -c 3 \
  "$stage/bin/firn-prewarm" --worker "$stage/bin/firn-prewarm" \
  "$main" "$expected_key" >"$scratch/detached.expected"
cmp "$scratch/detached.expected" "$scratch/detached.plan"
: >"$FIRN_GALILEO_COUNT"
timeout --foreground 30 "$stage/bin/firn-prewarm" \
  --plan-reference-transaction "$stage/bin/firn-prewarm" committed \
  'abc def refs/heads/main' >"$scratch/hook.plan"
cmp "$scratch/detached.expected" "$scratch/hook.plan"
[[ "$(wc -l <"$FIRN_GALILEO_COUNT")" -eq 1 ]]
printf 'ok: --plan-reference-transaction spawns 1 query\n'
timeout --foreground 30 "$stage/bin/firn-prewarm" \
  --plan-reference-transaction "$stage/bin/firn-prewarm" prepared \
  'abc def refs/heads/main' >"$scratch/ignored.plan"
[[ ! -s "$scratch/ignored.plan" ]]
set +e
timeout --foreground 30 "$stage/bin/firn-prewarm" --unknown \
  >"$scratch/unknown.out" 2>"$scratch/unknown.err"
status=$?
set -e
[[ "$status" -eq 64 && ! -s "$scratch/unknown.out" ]]
rg -q '^usage: firn --print-warm-key$' "$scratch/unknown.err"
[[ ! -e "$runtime/firn-prewarm.lease" ]]
[[ ! -e "$runtime/firn-prewarm.owner" ]]
[[ ! -e "$runtime/firn-prewarm.warm" ]]

printf 'ok: Galileo/TypeScript Firn prewarm producer and Bun plan adapter pass\n'
