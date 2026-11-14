import { parseAuthoringArgv, planAuthoring, schemaEntriesFromJson, safeSecretName, stripYamlSuffix, type AuthoringAction, type SchemaEntry } from './authoring.ts';

type HostResult = { tag: 'error'; errno: number } | { tag: 'ok'; kind?: number; text?: string; entries?: string[] };
export interface AuthoringBridge {
  getenv(name: string): string | null;
  pathKind(path: string): HostResult;
  readTextBounded(path: string, limit: number): HostResult;
  makeParentDirectories(path: string): HostResult;
  writeTextAtomic(path: string, text: string): HostResult;
  listDirectoryBounded(path: string, limit: number): HostResult;
  runInherit(argv: string[]): number;
  runNix(root: string, argv: string[]): number;
  out(text: string): void;
  err(text: string): void;
}
const path = (root: string, relative: string) => root + '/' + relative;
const errnoMessage = (operation: string, relative: string, errno: number) => `firn authoring: ${operation} '${relative}': errno ${errno}\n`;
function emitError(bridge: AuthoringBridge, message: string): number { bridge.err(message); return 1; }
function childStatus(bridge: AuthoringBridge, tool: string, status: number): number {
  return status < 0 ? emitError(bridge, `firn authoring: cannot run ${tool}: errno ${-status}\n`) : status;
}
function loadSchema(bridge: AuthoringBridge, root: string): SchemaEntry[] | string {
  const relative = '.firn-cache/schema.json', absolute = path(root, relative);
  const kind = bridge.pathKind(absolute);
  if (kind.tag === 'error') return kind.errno === 2 ? [] : errnoMessage('cannot inspect schema', relative, kind.errno);
  if (kind.kind !== 1 && kind.kind !== 3) return `firn authoring: schema is not a file '${relative}'\n`;
  const read = bridge.readTextBounded(absolute, 67108864);
  if (read.tag === 'error') return errnoMessage('cannot read schema', relative, read.errno);
  const parsed = schemaEntriesFromJson(String(read.text));
  return parsed._tag === 'SchemaParsed' ? parsed.entries : `firn authoring: invalid schema '${relative}' at offset ${parsed.offset}: ${parsed.message}\n`;
}
function runScaffold(bridge: AuthoringBridge, root: string, action: AuthoringAction): number {
  const schema = action._tag === 'TemplateService' ? loadSchema(bridge, root) : [];
  if (typeof schema === 'string') return emitError(bridge, schema);
  const result = planAuthoring(action, schema);
  if (result._tag === 'AuthoringPlanRejected') return emitError(bridge, result.message);
  const plan = result.plan;
  if (action._tag === 'ModuleAdd') {
    const relative = `modules/${action.name}`, inspected = bridge.pathKind(path(root, relative));
    if (inspected.tag === 'ok') return emitError(bridge, `Module ${action.name} already exists\n`);
    if (inspected.errno !== 2) return emitError(bridge, errnoMessage('cannot inspect', relative, inspected.errno));
  }
  for (const target of plan.targets) {
    const absolute = path(root, target.relative), inspected = bridge.pathKind(absolute);
    if (inspected.tag === 'ok') return emitError(bridge, `firn scaffold: refusing to overwrite ${absolute}\n`);
    if (inspected.errno !== 2) return emitError(bridge, errnoMessage('cannot inspect', target.relative, inspected.errno));
  }
  for (const target of plan.targets) {
    const absolute = path(root, target.relative), parent = bridge.makeParentDirectories(absolute);
    if (parent.tag === 'error') return emitError(bridge, errnoMessage('cannot create parent for', target.relative, parent.errno));
    const write = bridge.writeTextAtomic(absolute, target.contents);
    if (write.tag === 'error') return emitError(bridge, errnoMessage('cannot write', target.relative, write.errno));
  }
  const files = plan.targets.map(target => target.relative);
  const checked = bridge.runNix(root, files.filter(file => file.endsWith('.nix')));
  if (checked !== 0) return childStatus(bridge, 'nix-instantiate', checked);
  const staged = bridge.runInherit(['git', '-C', root, 'add', '--', ...plan.targets.map(target => path(root, target.relative))]);
  if (staged !== 0) return childStatus(bridge, 'git', staged);
  bridge.out(plan.success_output);
  return 0;
}
function loadSecretNames(bridge: AuthoringBridge, root: string): string[] | string {
  const listed = bridge.listDirectoryBounded(path(root, 'secrets'), 16384);
  if (listed.tag === 'error') return listed.errno === 2 || listed.errno === 20 ? [] : errnoMessage('cannot list', 'secrets', listed.errno);
  const names: string[] = [];
  for (const entry of listed.entries!) {
    if (!entry.endsWith('.yaml') || !safeSecretName(stripYamlSuffix(entry))) continue;
    const relative = `secrets/${entry}`, inspected = bridge.pathKind(path(root, relative));
    if (inspected.tag === 'error') {
      if (inspected.errno === 2) continue;
      return errnoMessage('cannot inspect', relative, inspected.errno);
    }
    if (inspected.kind === 1) names.push(stripYamlSuffix(entry));
  }
  return names;
}
function runSecret(bridge: AuthoringBridge, root: string, action: AuthoringAction): number {
  if (action._tag !== 'SecretList' && !safeSecretName((action as {name: string}).name)) return emitError(bridge, 'firn secret: invalid secret name\n');
  const names = loadSecretNames(bridge, root);
  if (typeof names === 'string') return emitError(bridge, names);
  if (action._tag === 'SecretList') { bridge.out(names.map(name => name + '\n').join('')); return 0; }
  const name = (action as {name: string}).name;
  const missing = () => emitError(bridge, `No secret file: secrets/${name}.yaml\n`);
  if (!names.includes(name)) return missing();
  const absolute = path(root, `secrets/${name}.yaml`);
  if (action._tag === 'SecretShow') return childStatus(bridge, 'sops', bridge.runInherit(['sops', '-d', absolute]));
  const edited = bridge.runInherit(['sops', absolute]);
  if (edited !== 0) return childStatus(bridge, 'sops', edited);
  const inspected = bridge.pathKind(absolute);
  if (inspected.tag === 'error' || inspected.kind !== 1) return missing();
  const staged = bridge.runInherit(['git', '-C', root, 'add', '--', absolute]);
  if (staged !== 0) return childStatus(bridge, 'git', staged);
  bridge.out(`secrets/${name}.yaml (git added)\n`);
  return 0;
}
export function run(bridge: AuthoringBridge, args: string[]): number {
  const parsed = parseAuthoringArgv(args);
  if (parsed._tag === 'InvalidAuthoringArgv') {
    bridge.err('Usage: firn module add <name>\n       firn template service <name>\n       firn template submodule <name>\n       firn template home <name>\n       firn template host <name>\n       firn secret list [all]\n       firn secret show <name>\n       firn secret edit <name>\n');
    return 64;
  }
  const explicit = bridge.getenv('FIRN_REPO');
  const home = explicit === null ? bridge.getenv('HOME') : null;
  const root = explicit ?? (home === null ? null : home + '/code/nixos-config/main');
  if (root === null) return emitError(bridge, 'firn authoring: FIRN_REPO and HOME are not set\n');
  return parsed.action._tag.startsWith('Secret') ? runSecret(bridge, root, parsed.action) : runScaffold(bridge, root, parsed.action);
}
