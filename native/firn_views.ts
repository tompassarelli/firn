import { decode, type JsonEvent } from './native_json.ts';

export type Follow = { input: string; target: string };
export type FlakeRow = { name: string; url: string; ageSeconds: number; age: string; revision: string; frozen: boolean; broken: boolean; follows: Follow[] };
export type FlakeRowsResult = { _tag: 'FlakeRows'; rows: FlakeRow[] } | { _tag: 'FlakeRowsRejected'; message: string };
export type PlatformRow = { module: string; platform: string };
export type PlatformVerdict = { module: string; verdict: 'both' | 'linux-only' | 'darwin-only' | 'neither'; blockers: string[] };
export type QueryNamesResult = { _tag: 'QueryNames'; names: string[] } | { _tag: 'QueryNamesRejected'; message: string };
export type QueryRowsResult = { _tag: 'QueryRows'; rows: PlatformRow[] } | { _tag: 'QueryRowsRejected'; message: string };
export type ChildResult = { status: number; stdout: string; stderr: string };
export type CommandResult = ChildResult;
export type ViewsAction = { _tag: 'FlakeInputs'; token: boolean } | { _tag: 'PlatformList'; selection: string } | { _tag: 'PlatformShow'; module: string } | { _tag: 'PlatformSafelist'; token: boolean } | { _tag: 'SchemaExplain'; input: string } | { _tag: 'HostGeneration'; host: string };
export type ViewsArgv = { _tag: 'ParsedViews'; action: ViewsAction } | { _tag: 'InvalidViewsArgv'; argv: string[] };

export const platformRow = (module: string, platform: string): PlatformRow => ({ module, platform });
export const childResult = (status: number, stdout: string, stderr: string): ChildResult => ({ status, stdout, stderr });
export const startsWith = (text: string, prefix: string): boolean => text.startsWith(prefix);
export const endsWith = (text: string, suffix: string): boolean => text.endsWith(suffix);
const appendUnique = (values: string[], candidate: string): string[] => values.includes(candidate) ? values : [...values, candidate];
const splitLines = (text: string): string[] => {
  const lines = text.split('\n');
  if (lines.at(-1) === '') lines.pop();
  return lines;
};
const trimSpaces = (text: string): string => text.replace(/^[ \t]+/, '').replace(/[ \t\r]+$/, '');
const padRight = (text: string, width: number): string => text.padEnd(width, ' ');
const truncate = (text: string, limit: number): string => text.length <= limit ? text : text.slice(0, limit - 1) + '…';
const ansi = (tty: boolean, code: string, text: string): string => tty ? `\u001b[${code}m${text}\u001b[0m` : text;

function jsonContainerEnd(events: JsonEvent[], start: number): number {
  let depth = 0;
  for (let index = start; index < events.length; index++) {
    const tag = events[index].tag;
    if (tag === 'JsonObjectStart' || tag === 'JsonArrayStart') depth++;
    else if (tag === 'JsonObjectEnd' || tag === 'JsonArrayEnd') {
      if (depth === 1) return index + 1;
      depth--;
    }
  }
  return -1;
}

function jsonValueEnd(events: JsonEvent[], start: number): number {
  if (start < 0 || start >= events.length) return -1;
  switch (events[start].tag) {
    case 'JsonObjectStart': case 'JsonArrayStart': return jsonContainerEnd(events, start);
    case 'JsonObjectEnd': case 'JsonArrayEnd': return -1;
    default: return start + 1;
  }
}

function objectFieldStart(events: JsonEvent[], start: number, key: string): number {
  if (start < 0 || start >= events.length || events[start].tag !== 'JsonObjectStart') return -1;
  const end = jsonValueEnd(events, start);
  if (end < 0) return -1;
  for (let index = start + 1; index < end - 1;) {
    const event = events[index];
    if (event.tag !== 'JsonKey') return -1;
    const valueIndex = index + 1;
    const next = jsonValueEnd(events, valueIndex);
    if (next < 0) return -1;
    if (event.value === key) return valueIndex;
    index = next;
  }
  return -1;
}

function objectFieldNames(events: JsonEvent[], start: number): string[] {
  if (start < 0 || start >= events.length || events[start].tag !== 'JsonObjectStart') return [];
  const end = jsonValueEnd(events, start);
  if (end < 0) return [];
  const names: string[] = [];
  for (let index = start + 1; index < end - 1;) {
    const event = events[index];
    if (event.tag !== 'JsonKey') return [];
    const next = jsonValueEnd(events, index + 1);
    if (next < 0) return [];
    names.push(event.value);
    index = next;
  }
  return names;
}

function stringAt(events: JsonEvent[], index: number): string | null {
  const event = events[index];
  return event?.tag === 'JsonString' ? event.value : null;
}

function parseLong(text: string): number {
  return parseInt(text, 10);
}

function numberAt(events: JsonEvent[], index: number): number | null {
  const event = events[index];
  return event?.tag === 'JsonNumber' ? parseLong(event.lexeme) : null;
}
const objectString = (events: JsonEvent[], start: number, key: string): string | null => stringAt(events, objectFieldStart(events, start, key));
const objectNumber = (events: JsonEvent[], start: number, key: string): number | null => numberAt(events, objectFieldStart(events, start, key));

function arrayStrings(events: JsonEvent[], start: number): string[] {
  if (start < 0 || start >= events.length || events[start].tag !== 'JsonArrayStart') return [];
  const end = jsonValueEnd(events, start);
  const values: string[] = [];
  for (let index = start + 1; index < end - 1;) {
    const next = jsonValueEnd(events, index);
    const value = stringAt(events, index);
    if (next < 0) return [];
    if (value !== null) values.push(value);
    index = next;
  }
  return values;
}

export function humanAge(seconds: number): string {
  const safe = Math.max(seconds, 0);
  const minutes = Math.trunc(safe / 60);
  const hours = Math.trunc(minutes / 60);
  const days = Math.trunc(hours / 24);
  if (safe < 60) return `${safe}s`;
  if (minutes < 60) return `${minutes}m`;
  if (hours < 24) return `${hours}h`;
  if (days < 30) return `${days}d`;
  if (days < 365) return `${Math.trunc(days / 30)}mo`;
  return `${Math.trunc(days / 365)}y`;
}

function originalUrl(events: JsonEvent[], original: number): string {
  const type = objectString(events, original, 'type') ?? '';
  const url = objectString(events, original, 'url');
  const owner = objectString(events, original, 'owner') ?? '';
  const repo = objectString(events, original, 'repo') ?? '';
  const reference = objectString(events, original, 'ref');
  const revision = objectString(events, original, 'rev');
  const path = objectString(events, original, 'path') ?? '';
  if (url !== null) return url;
  if (type === 'github') {
    const suffix = reference ?? revision ?? '';
    return `github:${owner}/${repo}${suffix === '' ? '' : '/' + suffix}`;
  }
  if (type === 'gitlab') return `gitlab:${owner}/${repo}`;
  if (type === 'git') return `git+${url ?? ''}`;
  if (type === 'path') return `path:${path}`;
  return `${type}:?`;
}

function followsFromNode(events: JsonEvent[], node: number): Follow[] {
  const inputs = objectFieldStart(events, node, 'inputs');
  const result: Follow[] = [];
  for (const name of objectFieldNames(events, inputs)) {
    const values = arrayStrings(events, objectFieldStart(events, inputs, name));
    if (values.length > 0) result.push({ input: name, target: values[values.length - 1] });
  }
  return result;
}

function flakeRow(events: JsonEvent[], nodes: number, rootInputs: number, name: string, nowSeconds: number): FlakeRow | null {
  const inputValue = objectFieldStart(events, rootInputs, name);
  const values = arrayStrings(events, inputValue);
  const nodeName = stringAt(events, inputValue) ?? (values.length === 0 ? name : values[0]);
  const node = objectFieldStart(events, nodes, nodeName);
  const original = objectFieldStart(events, node, 'original');
  const locked = objectFieldStart(events, node, 'locked');
  if (node < 0 || original < 0) return null;
  const modified = objectNumber(events, locked, 'lastModified');
  const ageSeconds = modified === null ? -1 : Math.max(0, nowSeconds - modified);
  return {
    name, url: originalUrl(events, original), ageSeconds,
    age: ageSeconds < 0 ? '?' : humanAge(ageSeconds),
    revision: (objectString(events, locked, 'rev') ?? '?').slice(0, 8),
    frozen: objectString(events, original, 'rev') !== null,
    broken: objectString(events, original, 'type') === 'path' && (objectString(events, original, 'path') ?? '').startsWith('/'),
    follows: followsFromNode(events, node),
  };
}

function rowBefore(left: FlakeRow, right: FlakeRow): boolean {
  const leftAge = left.ageSeconds < 0 ? 315360000 : left.ageSeconds;
  const rightAge = right.ageSeconds < 0 ? 315360000 : right.ageSeconds;
  return leftAge < rightAge || leftAge === rightAge && left.name < right.name;
}

export function flakeRows(source: string, nowSeconds: number): FlakeRowsResult {
  const decoded = decode(source);
  if (decoded.tag === 'JsonDecodeError') return { _tag: 'FlakeRowsRejected', message: `invalid flake.lock at ${decoded.offset}: ${decoded.message}` };
  const events = decoded.events;
  if (events.length === 0 || events[0].tag !== 'JsonObjectStart') return { _tag: 'FlakeRowsRejected', message: 'flake.lock must be a JSON object' };
  const rootName = objectString(events, 0, 'root') ?? 'root';
  const nodes = objectFieldStart(events, 0, 'nodes');
  const rootNode = objectFieldStart(events, nodes, rootName);
  const rootInputs = objectFieldStart(events, rootNode, 'inputs');
  const names = objectFieldNames(events, rootInputs).sort();
  if (nodes < 0 || rootNode < 0 || rootInputs < 0) return { _tag: 'FlakeRowsRejected', message: 'flake.lock is missing root nodes/inputs' };
  const rows: FlakeRow[] = [];
  for (const name of names) {
    const row = flakeRow(events, nodes, rootInputs, name, nowSeconds);
    if (row === null) return { _tag: 'FlakeRowsRejected', message: `flake.lock input '${name}' has no lock node` };
    const index = rows.findIndex(current => rowBefore(row, current));
    rows.splice(index < 0 ? rows.length : index, 0, row);
  }
  return { _tag: 'FlakeRows', rows };
}

export function renderFlakeRows(rows: FlakeRow[], tty: boolean): string {
  if (rows.length === 0) return 'No inputs in flake.lock.\n';
  const nameWidth = rows.reduce((width, row) => Math.max(width, row.name.length), 0);
  const broken = rows.filter(row => row.broken);
  let text = broken.length === 0 ? '' : `! ${broken.length} input${broken.length === 1 ? '' : 's'} with absolute path${broken.length === 1 ? '' : 's'} (would break the build):\n` + broken.map(row => `    ${row.name}: ${row.url}\n`).join('') + '\n';
  text += `${ansi(tty, '1', 'flake inputs')} (${rows.length}, newest first)\n  ${padRight('name', nameWidth)}  ${padRight('source', 57)}  age    rev\n`;
  for (const row of rows) {
    const source = truncate(row.url, 48) + (row.frozen ? ' [frozen]' : '');
    text += `  ${padRight(row.name, nameWidth)}  ${padRight(source, 57)}  ${padRight(row.age, 5)}  ${row.revision}\n`;
    for (const follow of row.follows) text += `  ${padRight('', nameWidth)}  └─ ${follow.input} shares ${follow.target}\n`;
  }
  return text + '\n→ `nix flake update <name>` bumps one input; `nix flake update` bumps all.\n'
    + (rows.some(row => row.frozen) ? '→ [frozen] = source URL pins a commit; it will not update.\n' : '')
    + (rows.some(row => row.follows.length > 0) ? '→ └─ X shares Y = this input uses our copy of Y.\n' : '');
}

function arrayElements(events: JsonEvent[]): number[] | null {
  if (events.length === 0 || events[0].tag !== 'JsonArrayStart') return null;
  const end = jsonValueEnd(events, 0);
  if (end !== events.length) return null;
  const starts: number[] = [];
  for (let index = 1; index < end - 1;) {
    const next = jsonValueEnd(events, index);
    if (next < 0) return null;
    starts.push(index);
    index = next;
  }
  return starts;
}

export function queryNamesFromJson(source: string): QueryNamesResult {
  const decoded = decode(source);
  if (decoded.tag === 'JsonDecodeError') return { _tag: 'QueryNamesRejected', message: decoded.message };
  const starts = arrayElements(decoded.events);
  if (starts === null) return { _tag: 'QueryNamesRejected', message: 'expected an array of names' };
  const names: string[] = [];
  for (const start of starts) {
    const name = stringAt(decoded.events, start);
    if (name === null) return { _tag: 'QueryNamesRejected', message: 'expected an array of names' };
    names.push(name);
  }
  return { _tag: 'QueryNames', names };
}

export function queryRowsFromJson(source: string): QueryRowsResult {
  const decoded = decode(source);
  if (decoded.tag === 'JsonDecodeError') return { _tag: 'QueryRowsRejected', message: decoded.message };
  const starts = arrayElements(decoded.events);
  if (starts === null) return { _tag: 'QueryRowsRejected', message: 'expected an array of rows' };
  const rows: PlatformRow[] = [];
  for (const start of starts) {
    const module = objectString(decoded.events, start, 'm');
    const platform = objectString(decoded.events, start, 'p');
    if (module === null || platform === null) return { _tag: 'QueryRowsRejected', message: 'expected rows with m and p' };
    rows.push({ module, platform });
  }
  return { _tag: 'QueryRows', rows };
}

export function platformMatrix(modules: string[], rows: PlatformRow[]): PlatformVerdict[] {
  return modules.map(module => {
    const linuxOk = rows.some(row => row.module === module && row.platform === 'linux');
    const darwinOk = rows.some(row => row.module === module && row.platform === 'darwin');
    if (linuxOk && darwinOk) return { module, verdict: 'both', blockers: [] };
    if (linuxOk) return { module, verdict: 'linux-only', blockers: ['darwin'] };
    if (darwinOk) return { module, verdict: 'darwin-only', blockers: ['linux'] };
    return { module, verdict: 'neither', blockers: ['darwin', 'linux'] };
  });
}

const modulesWith = (verdicts: PlatformVerdict[], verdict: PlatformVerdict['verdict']): string[] => verdicts.filter(row => row.verdict === verdict).map(row => row.module).sort();
const renderList = (label: string, modules: string[]): string => modules.length === 0 ? `${label} (0):  (none)\n` : `${label} (${modules.length}):\n` + modules.map(module => `  ${module}\n`).join('');

export function renderPlatformList(selection: string, verdicts: PlatformVerdict[]): CommandResult {
  const both = modulesWith(verdicts, 'both');
  const linux = modulesWith(verdicts, 'linux-only');
  const darwinOnly = modulesWith(verdicts, 'darwin-only');
  const darwin = darwinOnly.reduce(appendUnique, both).sort();
  const neither = modulesWith(verdicts, 'neither');
  if (selection === 'darwin') return childResult(0, renderList('darwin-compatible modules', darwin), '');
  if (selection === 'linux') return childResult(0, renderList('NixOS-only modules', linux) + (neither.length === 0 ? '' : '\n' + renderList('modules supported nowhere', neither)), '');
  if (selection === 'all') return childResult(0, `Platform compatibility matrix (${verdicts.length} modules)\n\n` + renderList('darwin-compatible modules', both) + '\n' + renderList('NixOS-only modules', linux) + (darwinOnly.length === 0 ? '' : '\n' + renderList('darwin-only modules', darwinOnly)) + (neither.length === 0 ? '' : '\n' + renderList('modules supported nowhere', neither)), '');
  return childResult(64, '', `firn platform list: expected all|darwin|linux, got '${selection}'\n`);
}

export const verdictFor = (verdicts: PlatformVerdict[], module: string): PlatformVerdict | null => verdicts.find(row => row.module === module) ?? null;

export function renderPlatformShow(module: string, verdicts: PlatformVerdict[]): CommandResult {
  const verdict = verdictFor(verdicts, module);
  if (verdict === null) return childResult(1, '', `firn platform show: no module named '${module}'\n`);
  return childResult(0, `module:  ${module}\nverdict: ${verdict.verdict}\n` + (verdict.blockers.length === 0 ? '' : 'unsupported on:\n' + verdict.blockers.map(platform => `  ${platform}\n`).join('')), '');
}

export function renderPlatformSafelist(everywhere: PlatformRow[], supported: PlatformRow[]): CommandResult {
  const open = everywhere.reduce((values, row) => appendUnique(values, row.platform), [] as string[]).sort();
  const platforms = supported.reduce((values, row) => appendUnique(values, row.platform), [] as string[]).sort();
  let text = '';
  for (const platform of platforms) {
    if (open.includes(platform)) continue;
    const names = supported.filter(row => row.platform === platform).reduce((values, row) => appendUnique(values, row.module), [] as string[]).sort();
    if (names.length > 0) text += `${names.length === 1 ? names[0] : '[' + names.join(', ') + ']'} supports ${platform}\n`;
  }
  return childResult(0, text, '');
}

const allowedPathCharacter = (character: string): boolean => /^[a-zA-Z0-9._<>-]$/.test(character);
export const findSubstring = (text: string, needle: string): number => text.indexOf(needle);
function pathTokenAt(text: string, start: number): string | null {
  if (start < 0 || start >= text.length) return null;
  let end = start;
  while (end < text.length && allowedPathCharacter(text.slice(end, end + 1))) end++;
  return end === start ? null : text.slice(start, end);
}

export function extractOptionPath(input: string): string | null {
  const unknown = 'unknown option ';
  const mismatch = 'type mismatch at ';
  const unknownAt = findSubstring(input, unknown);
  const mismatchAt = findSubstring(input, mismatch);
  if (unknownAt >= 0) return pathTokenAt(input, unknownAt + unknown.length);
  if (mismatchAt >= 0) return pathTokenAt(input, mismatchAt + mismatch.length);
  const trimmed = trimSpaces(input);
  const candidate = pathTokenAt(trimmed, 0);
  return candidate !== null && candidate === trimmed ? candidate : null;
}

export function renderHostGeneration(child: ChildResult): CommandResult {
  if (child.status !== 0) return childResult(child.status, child.stdout, child.stderr + 'firn host gen: generation listing failed.\n');
  let generation: number | null = null;
  for (const line of splitLines(child.stdout)) {
    if (line.includes('current') || trimSpaces(line).endsWith('True')) {
      generation = parseLong(trimSpaces(line).split(/[ \t]/, 1)[0]);
      break;
    }
  }
  return generation === null ? childResult(0, '(no generation info)\n', '') : childResult(0, `current: ${generation}\nnext:    ${generation + 1}\n`, '');
}

export function parseViewsArgv(argv: string[], currentHost: string): ViewsArgv {
  let action: ViewsAction | null = null;
  const equals = (expected: string[]) => argv.length === expected.length && argv.every((value, index) => value === expected[index]);
  if (equals(['flake', 'inputs']) || equals(['flake', 'inputs', 'all'])) action = { _tag: 'FlakeInputs', token: false };
  else if (equals(['platform', 'list'])) action = { _tag: 'PlatformList', selection: 'all' };
  else if (argv.length === 3 && argv[0] === 'platform' && argv[1] === 'list') action = { _tag: 'PlatformList', selection: argv[2] };
  else if (argv.length === 3 && argv[0] === 'platform' && argv[1] === 'show') action = { _tag: 'PlatformShow', module: argv[2] };
  else if (equals(['platform', 'safelist', 'all']) || equals(['platform', 'safelist'])) action = { _tag: 'PlatformSafelist', token: false };
  else if (argv.length === 3 && argv[0] === 'schema' && argv[1] === 'explain') action = { _tag: 'SchemaExplain', input: argv[2] };
  else if (equals(['host', 'gen'])) action = { _tag: 'HostGeneration', host: currentHost };
  else if (argv.length === 3 && argv[0] === 'host' && argv[1] === 'gen') action = { _tag: 'HostGeneration', host: argv[2] };
  return action === null ? { _tag: 'InvalidViewsArgv', argv } : { _tag: 'ParsedViews', action };
}
