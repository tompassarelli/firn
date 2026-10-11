#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
workbench="${FIRN_CLAUSE_WORKBENCH:-${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/current/bin/clause-workbench}"
bun="${FIRN_BUN:-${BUN:-$(command -v bun || true)}}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-prewarm-clause.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'prewarm-clause: retained failure artifacts at %s\n' "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

[[ -x "$workbench" ]] || { printf 'prewarm-clause: missing Clause compiler: %s\n' "$workbench" >&2; exit 1; }
[[ -x "$bun" ]] || { printf 'prewarm-clause: missing Bun; set FIRN_BUN\n' >&2; exit 1; }

# Exercise the producer's exact materializer without building unrelated families.
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
ln -s "$workbench" "$stage/bin/clause-workbench"
ln -s "$bun" "$stage/bin/bun"
materialize_js prewarm firn-prewarm prewarm.js FIRN_PREWARM_MODULE \
  "$here/prewarm_host.mjs" "$here/prewarm.clause"
rg -q '^component=prewarm module=lib/prewarm/prewarm.js executable=bin/firn-prewarm runtime=bun$' "$manifest"
rg -q '^artifact=prewarm-types path=lib/prewarm/prewarm.d.ts ' "$manifest"

POLICY="$stage/lib/prewarm/prewarm.js" "$bun" - <<'JS'
import assert from 'node:assert/strict';
const p = await import(process.env.POLICY);
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
assert.deepEqual(p['parse-lease-owner'](`101\n102\n${key}\n`), owner);
assert.deepEqual(p['parse-lease-owner'](` +101suffix\n102\n${key}`), owner);
for (const text of ['', `101\n102\n${key}\n\n`, `101\n\n${key}\n`, `0\n102\n${key}\n`, '101\n102\n\n']) {
  assert.ok('message' in p['parse-lease-owner'](text), JSON.stringify(text));
}
const executable = '/bin/firn';
const repository = snapshot.repository;
const worker = {pid:101, argv:[executable,'--worker',executable,repository,key]};
const child = {pid:102, argv:['nix','build','--no-link','--print-out-paths',key]};
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
console.log('ok: checked Clause prewarm policy, typed plans, parsing and identity guards');
JS

container="$scratch/container"
main="$container/main"
lane="$container/worktrees/slug"
runtime="$scratch/runtime"
host="$(hostname)"
mkdir -p "$main/native" "$main/hosts/$host" "$container/worktrees" "$runtime"
printf 'export fixture(): Text\n  "firn"\n' >"$main/native/firn.clause"
printf '#lang beagle/nix\n(ns flake)\n' >"$main/flake.bnix"
printf 'fixture\n' >"$main/hosts/$host/marker"
git init -q -b main "$main"
git -C "$main" add -- native/firn.clause flake.bnix "hosts/$host/marker"
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
actual_key="$(timeout --foreground 30 "$stage/bin/firn-prewarm" --print-warm-key)"
[[ "$actual_key" == "$expected_key" ]]

timeout --foreground 30 "$stage/bin/firn-prewarm" \
  --plan-detached "$stage/bin/firn-prewarm" >"$scratch/detached.plan"
printf '%s\n' setsid -f nice -n 19 ionice -c 3 \
  "$stage/bin/firn-prewarm" --worker "$stage/bin/firn-prewarm" \
  "$main" "$expected_key" >"$scratch/detached.expected"
cmp "$scratch/detached.expected" "$scratch/detached.plan"
timeout --foreground 30 "$stage/bin/firn-prewarm" \
  --plan-reference-transaction "$stage/bin/firn-prewarm" committed \
  'abc def refs/heads/main' >"$scratch/hook.plan"
cmp "$scratch/detached.expected" "$scratch/hook.plan"
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

printf 'ok: Clause/JS Firn prewarm producer and Bun plan adapter pass\n'
