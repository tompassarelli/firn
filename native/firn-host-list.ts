import { dirname } from 'node:path';
import { listDirectory, pathKind } from './firn-host-list-os.mjs';

type Policy = { length: number; leaf: string };
type CommandResult = { output: string; error: string; status: number };
const maxEntries = 16384;
const missingPath = 2;
const directoryKind = 2;
let policies: Policy[] | undefined;
function policy(): Policy[] {
  if (policies) return policies;
  const bin = process.env.FIRN_RUNTIME_BIN ?? '';
  const galileo = process.env.FIRN_GALILEO ?? `${bin}/galileo`;
  const source = process.env.FIRN_GALILEO_HOST_LIST ?? `${bin}/../lib/firn/host-list.gal`;
  const child = Bun.spawnSync({ cwd: dirname(dirname(dirname(source))), cmd: [galileo, 'query', source,
    'all ?length, ?leaf where ?policy accepts length ?length leaf ?leaf', '--json'], stdout: 'pipe', stderr: 'pipe' });
  if (child.exitCode !== 0) throw new Error(`firn: galileo host-list query failed\n${new TextDecoder().decode(child.stderr)}`);
  policies = JSON.parse(new TextDecoder().decode(child.stdout));
  return policies!;
}
export function handles(args: string[]): boolean {
  return args[0] === 'host' && args[1] === 'list'
    && policy().some(row => row.length === args.length && row.leaf === (args[2] ?? ''));
}
export function hostList(root: string): CommandResult {
  const failure = (operation: string, path: string, status: number): CommandResult => ({output: '', error: `firn host list: ${operation} '${path}': errno ${status}\n`, status: 1});
  const directory = listDirectory(`${root}/hosts`);
  if (directory.status !== 0 && directory.status !== missingPath) return failure('cannot list', 'hosts', directory.status);
  if (directory.names.length > maxEntries) return failure('cannot list', 'hosts', 27);
  const names: string[] = [];
  for (const name of directory.names) {
    const entry = pathKind(`${root}/hosts/${name}`);
    if (entry.status !== 0 && entry.status !== missingPath) return failure('cannot inspect', `hosts/${name}`, entry.status);
    if (entry.status === 0 && entry.kind === directoryKind) names.push(name);
  }
  names.sort();
  return {output: `Hosts (${names.length}):\n${names.map(name => `  ${name}\n`).join('')}`, error: '', status: 0};
}
export function run(root: string, args: string[]): number {
  const result = handles(args) ? hostList(root) : {output: '', error: 'Usage: firn host list [all]\n', status: 64};
  process.stdout.write(result.output);
  process.stderr.write(result.error);
  return result.status;
}
