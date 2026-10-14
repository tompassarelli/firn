import { listDirectory, pathKind } from './firn-host-list-os.mjs';

type CommandResult = { output: string; error: string; status: number };
const maxEntries = 16384;
const missingPath = 2;
const directoryKind = 2;
export function handles(args: string[]): boolean {
  return args[0] === 'host' && args[1] === 'list'
    && (args.length === 2 || args.length === 3 && args[2] === 'all');
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
