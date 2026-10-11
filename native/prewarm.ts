import { dirname } from 'node:path';
type Invalid = { message: string };
type Owner = { 'worker-pid': number; 'child-pid': number; key: string };
type Identity = { pid: number; argv: string[] };
type Snapshot = { repository: string; revision: string; branch: string; host: string; platform: string };
type Policy = { platform: string; prefix: string; suffix: string; action: string; identity: boolean; same: boolean; success: boolean; cancelled: boolean; bounded: boolean; committed: boolean; updated: boolean; node: string; edge: string };

const runtimeBin = process.env.FIRN_RUNTIME_BIN ?? '';
const galileo = process.env.FIRN_GALILEO ?? `${runtimeBin}/galileo`;
const source = process.env.FIRN_GALILEO_PREWARM ?? `${runtimeBin}/../lib/firn/prewarm.gal`;
function query<T>(question: string): T[] {
  const child = Bun.spawnSync({ cwd: dirname(dirname(dirname(source))), cmd: [galileo, 'query', source, question, '--json'], stdout: 'pipe', stderr: 'pipe' });
  if (child.exitCode !== 0) throw new Error(`firn: galileo prewarm query failed\n${new TextDecoder().decode(child.stderr)}`);
  return JSON.parse(new TextDecoder().decode(child.stdout));
}
const build = ['nix', 'build', '--no-link', '--print-out-paths'];
const detached = ['setsid', '-f', 'nice', '-n', '19', 'ionice', '-c', '3'];
let policies: Policy[] | undefined;
function policy(): Policy[] {
  return policies ??= query<Policy>('all ?platform, ?prefix, ?suffix, ?action, ?identity, ?same, ?success, ?cancelled, ?bounded, ?committed, ?updated, ?node, ?edge where ?policy targets ?platform with prefix ?prefix suffix ?suffix and ?policy chooses lease ?action for identity ?identity same key ?same and ?policy writes stamp for success ?success cancelled ?cancelled bounded ?bounded and ?policy launches hook for committed ?committed updated main ?updated and ?policy recognizes rebuild ?node then ?edge');
}

function splitDelimited(text: string, delimiter: string): string[] {
  if (text === '') return [];
  const parts = text.split(delimiter);
  if (parts.at(-1) === '') parts.pop();
  return parts;
}
function containerMainCandidates(checkout: string, common: string | Invalid): string[] {
  const paths: string[] = [];
  for (const separator of ['/worktrees/', '/pins/']) {
    if (checkout.includes(separator)) { paths.push(`${checkout.split(separator)[0]}/main`); break; }
  }
  if (typeof common === 'string' && common.endsWith('/.git')) paths.push(common.slice(0, -5));
  paths.push(checkout);
  return [...new Set(paths)];
}
function shortHost(host: string): string { return host.split('.')[0]; }
function warmSpec(snapshot: Snapshot) {
  const uri = `git+file://${snapshot.repository}?rev=${snapshot.revision}${snapshot.branch === '' ? '' : `&ref=${snapshot.branch}`}`;
  const target = policy().find(row => row.platform === snapshot.platform)!;
  const attribute = `${target.prefix}${snapshot.host}${target.suffix}`;
  return {uri, attribute, key: `${uri}#${attribute}`};
}
function parseLeaseOwner(text: string): Owner | Invalid {
  const parts = splitDelimited(text, '\n');
  if (parts.length !== 3) return {message: 'expected worker pid, child pid, and key'};
  const worker = Number.parseInt(parts[0], 10), child = Number.parseInt(parts[1], 10);
  return worker > 0 && child > 0 && parts[2] !== ''
    ? {'worker-pid': worker, 'child-pid': child, key: parts[2]}
    : {message: 'invalid worker pid, child pid, or key'};
}
function renderOwner(owner: Owner): string { return `${owner['worker-pid']}\n${owner['child-pid']}\n${owner.key}\n`; }
function commandArgv(text: string): string[] { return text === '' ? [] : splitDelimited(text, text.at(-1)!); }
function workerArgv(executable: string, repository: string, key: string): string[] { return [executable, '--worker', executable, repository, key]; }
function nixBuildArgv(key: string): string[] { return [...build, key]; }
function detachedWorkerArgv(executable: string, repository: string, key: string): string[] { return [...detached, ...workerArgv(executable, repository, key)]; }
function supersedePlan(desired: string, current: number, executable: string, repository: string, owner: Owner, worker: Identity, child: Identity) {
  const matches = (identity: Identity, pid: number, argv: string[]) => identity.pid === pid && JSON.stringify(identity.argv) === JSON.stringify(argv);
  const identity = owner['worker-pid'] !== current
    && matches(worker, owner['worker-pid'], workerArgv(executable, repository, owner.key))
    && matches(child, owner['child-pid'], nixBuildArgv(owner.key));
  const action = policy().find(row => row.identity === identity && row.same === (desired === owner.key))!.action;
  return action === 'supersede' ? {'child-pid': owner['child-pid'], 'worker-pid': owner['worker-pid']}
    : {[action]: action === 'deduplicated' ? desired : owner.key};
}
function stampCurrent(stamp: string, key: string): boolean { return stamp.replace(/[\r\n]+$/u, '') === key; }
function stampPlan(key: string, status: number, cancelled: boolean, size: number, limit: number) {
  return policy().some(row => row.success === (status === 0) && row.cancelled === cancelled && row.bounded === (size <= limit))
    ? {text: `${key}\n`} : {status};
}
function hookPlan(state: string, lines: string[], executable: string, repository: string, key: string) {
  const updated = lines.some(line => {
    const fields = splitDelimited(line, ' ');
    return fields.length === 3 && fields[2] === 'refs/heads/main' && fields[0] !== fields[1] && !/^0+$/u.test(fields[1]);
  });
  return policy().some(row => row.committed === (state === 'committed') && row.updated === updated)
    ? {argv: detachedWorkerArgv(executable, repository, key)} : {state};
}
function rebuildArgv(argv: string[]): boolean {
  return argv.some((value, index) => (value === 'firn' || value.endsWith('/firn'))
    && policy().some(row => argv[index + 1] === row.node && (row.edge === '' || argv[index + 2] === row.edge)));
}
export {
  containerMainCandidates as 'container-main-candidates', shortHost as 'short-host', warmSpec as 'warm-spec',
  parseLeaseOwner as 'parse-lease-owner', renderOwner as 'render-owner', commandArgv as 'command-argv',
  workerArgv as 'worker-argv', nixBuildArgv as 'nix-build-argv', detachedWorkerArgv as 'detached-worker-argv',
  supersedePlan as 'supersede-plan', stampCurrent as 'stamp-current', stampPlan as 'stamp-plan',
  hookPlan as 'hook-plan', rebuildArgv as 'rebuild-argv',
};
