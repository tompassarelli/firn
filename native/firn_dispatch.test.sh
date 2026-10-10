#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
workbench="${FIRN_CLAUSE_WORKBENCH:-${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/current/bin/clause-workbench}"
bun="${FIRN_BUN:-$(command -v bun)}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-dispatch-clause.XXXXXX")"
cleanup() {
  local status=$?
  if ((status == 0)); then
    rm -rf -- "${scratch:?}"
  else
    printf 'firn-dispatch: retained failure artifacts at %s\n' "$scratch" >&2
  fi
}
trap cleanup EXIT

mkdir -p "$scratch/current/bin" "$scratch/current/lib"
"$workbench" compile-js "$here/firn.clause" "$scratch/current/lib/firn-dispatcher.js"
cp -- "$here/firn_io.mjs" "$scratch/current/bin/firn-io.mjs"
ln -s "$bun" "$scratch/current/bin/bun"
for family in tag flake-input inventory authoring views repo-build schema repo-workflow rebuild prewarm; do
  cat >"$scratch/current/bin/firn-$family" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "${0##*/}" "$@" >>"${FIRN_TEST_CALLS:?}"
printf '\n' >>"$FIRN_TEST_CALLS"
if [[ "${0##*/}" == "${FIRN_TEST_FAILURE_FAMILY:-}" ]]; then exit 23; fi
SH
  chmod +x "$scratch/current/bin/firn-$family"
done

FIRN_TEST_REPO="$repo" FIRN_TEST_SCRATCH="$scratch" FIRN_BUN="$bun" "$bun" - <<'JS'
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
const repo = process.env.FIRN_TEST_REPO;
const scratch = process.env.FIRN_TEST_SCRATCH;
const m = await import(`${scratch}/current/lib/firn-dispatcher.js`);
const plan = (args) => {
  const result = m['parse-dispatch'](args);
  assert.ok('steps' in result, JSON.stringify({ args, result }));
  return result.steps;
};
const diagnostic = (args, message, status = 1) => {
  assert.deepEqual(m['parse-dispatch'](args), { message, status, descriptor: status === 0 ? 1 : 2 });
};
const commands = m.commands();
assert.equal(m['command-count'](), 48);
assert.equal(commands.length, 48);
assert.equal(new Set(commands.map(c => `${c.node} ${c.edge}`)).size, 48);
const owners = [
  ['tag', 'resolve', 'tag'], ['flake-input', 'resolve', 'flake-input'],
  ['module', 'refs', 'inventory'], ['secret', 'edit', 'authoring'],
  ['platform', 'show', 'views'], ['repo', 'build', 'repo-build'],
  ['schema', 'extract', 'schema'], ['repo', 'doctor', 'repo-workflow'],
  ['repo', 'pin-ancestry', 'repo-workflow'], ['host', 'rebuild', 'rebuild'],
  ['host', 'prepare', 'rebuild'], ['host', 'activate', 'rebuild'], ['host', 'rollback', 'rebuild'],
];
for (const [node, edge, family] of owners) assert.equal(m['find-command'](node, edge).executable, `firn-${family}`);
assert.deepEqual(m['find-command']('repo', 'missing'), {node: 'repo', edge: 'missing'});
assert.equal(m['find-command']('secret', 'edit').summary, 'open an existing secret in $EDITOR via sops');
for (const c of commands) {
  const required = 'required' in c.leaf;
  const args = [c.node, c.edge, ...(required ? ['fixture'] : [])];
  assert.deepEqual(plan(args), [{executable: c.executable, arguments: [c.node, c.edge, ...(required ? ['fixture'] : c.leaf.arguments)]}]);
  if (required) diagnostic([c.node, c.edge], `firn: '${c.node} ${c.edge}' requires a leaf node\nUsage: firn ${c.node} ${c.edge} ${c.leaf.required}\n  ${c.summary}\n`);
}
for (const [args, leaf] of [[['repo', 'upgrade'], ['now']], [['flake-input', 'resolve'], ['emit']], [['host', 'status'], []], [['tag', 'index'], ['repo']]]) {
  assert.deepEqual(plan(args)[0].arguments, [...args, ...leaf]);
}
const chain = ['repo', 'build', 'repo', 'validate', 'tag', 'enable', 'terminal', 'module', 'list', 'used'];
assert.deepEqual(plan(chain), [
  {executable:'firn-repo-build', arguments:['repo','build','all']},
  {executable:'firn-schema', arguments:['repo','validate','all']},
  {executable:'firn-tag', arguments:['tag','enable','terminal']},
  {executable:'firn-inventory', arguments:['module','list','used']},
]);
assert.deepEqual(plan(['module','list','repo']), [{executable:'firn-inventory',arguments:['module','list','repo']}]);
assert.deepEqual(plan(['rebuild']), [{executable:'firn-rebuild',arguments:['host','rebuild']}]);
assert.deepEqual(plan(['rebuild','whiterabbit']), [{executable:'firn-rebuild',arguments:['host','rebuild','whiterabbit']}]);
assert.deepEqual(plan(['rollback','40']), [{executable:'firn-rebuild',arguments:['host','rollback','40']}]);
for (const args of [['rebuild','--bad'],['rebuild','host','extra']]) diagnostic(args, 'Usage: firn rebuild [host]\n');
for (const args of [['rollback'],['rollback','--bad'],['rollback','40','extra']]) diagnostic(args, 'Usage: firn rollback <generation>\n');
const help = readFileSync(`${repo}/native/fixtures/firn-help.txt`, 'utf8');
assert.equal(m['full-help-text'](), help);
for (const args of [[], ['help'], ['-h'], ['--help','ignored']]) diagnostic(args, help, 0);
diagnostic(['repo'], m['node-help-text']('repo'), 0);
diagnostic(['repo','missing'], m['unknown-walk-text']('repo','missing'));
diagnostic(['missing'], m['incomplete-walk-text']());
diagnostic(['tag','enable','terminal','loose'], 'firn: dangling token after a complete walk: loose\n');
for (const mode of ['--print-warm-key','--plan-detached','--plan-reference-transaction','--reference-transaction','--worker']) {
  assert.deepEqual(plan([mode,'value with spaces']), [{executable:'firn-prewarm',arguments:[mode,'value with spaces']}]);
}
const callsPath = `${scratch}/calls`;
function cli(args, extra = {}) {
  writeFileSync(callsPath, '');
  const env = { ...process.env, FIRN_REPO:repo, FIRN_RUNTIME_ROOT:scratch, FIRN_TEST_CALLS:callsPath, ...extra };
  delete env.FIRN_DISPATCHER_MODULE;
  const child = Bun.spawnSync(['bash', `${repo}/dotfiles/bin/firn`, ...args], {cwd:repo, env, stdout:'pipe', stderr:'pipe'});
  const raw = readFileSync(callsPath, 'utf8');
  return {status:child.exitCode, out:new TextDecoder().decode(child.stdout), err:new TextDecoder().decode(child.stderr), calls:raw ? raw.trimEnd().split('\n').map(row => row.split('\0').slice(0,-1)) : []};
}
assert.deepEqual(cli(['--help']), {status:0,out:help,err:'',calls:[]});
assert.deepEqual(cli(['module','add']), {status:1,out:'',err:"firn: 'module add' requires a leaf node\nUsage: firn module add <name>\n  scaffold a minimal module (.bnix + .nix)\n",calls:[]});
assert.deepEqual(cli(chain), {status:0,out:'',err:'',calls:plan(chain).map(step=>[step.executable,...step.arguments])});
assert.deepEqual(cli(chain,{FIRN_TEST_FAILURE_FAMILY:'firn-schema'}), {status:23,out:'',err:'',calls:[['firn-repo-build','repo','build','all'],['firn-schema','repo','validate','all']]});
assert.deepEqual(cli(['tag','enable','terminal','unknown','edge']), {status:1,out:'',err:m['unknown-walk-text']('unknown','edge'),calls:[]});
for (const [node, edge] of owners) {
  const c=m['find-command'](node,edge);
  const args=[node,edge,...('required' in c.leaf ? ['fixture'] : [])];
  assert.deepEqual(cli(args), {status:0,out:'',err:'',calls:plan(args).map(step=>[step.executable,...step.arguments])});
}
for (const args of [['rebuild'],['rebuild','whiterabbit'],['rollback','40'],['--worker','value with spaces']]) {
  assert.deepEqual(cli(args), {status:0,out:'',err:'',calls:plan(args).map(step=>[step.executable,...step.arguments])});
}
const hosts=cli(['host','list','all']);
assert.equal(hosts.status,0); assert.equal(hosts.err,''); assert.match(hosts.out,/^  whiterabbit$/m);
assert.deepEqual(hosts.calls,[]);
const inferred=cli(['repo','build'],{FIRN_REPO:undefined});
assert.equal(inferred.status,0); assert.deepEqual(inferred.calls,[['firn-repo-build','repo','build','all']]);
console.log('PASS firn-dispatch: 48 commands, defaults, help, diagnostics, aliases, chains, early exit, prewarm, and ordinary launcher');
JS
