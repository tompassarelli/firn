import * as quality from './repo_quality.ts';
import { decode, type JsonEvent } from './native_json.ts';

export type RepoWorkflowAction =
  | { kind: 'RepoValidate' | 'RepoLint' | 'RepoDoctor' | 'RepoPinAncestry' | 'RepoWatch'; token: boolean }
  | { kind: 'RepoDiff'; target: string }
  | { kind: 'RepoArchitecture'; bundle: boolean }
  | { kind: 'RepoUpgrade'; dryRun: boolean };
export type RepoWorkflowArgv =
  | { kind: 'ParsedRepoWorkflow'; action: RepoWorkflowAction }
  | { kind: 'InvalidRepoWorkflowArgv'; argv: string[] };
export type ProcessObservation = { status: number; stdout: string; stderr: string };
type FirstPartyInput = { name: string; repo: string; rev: string };
type FirstPartyInputsResult = { kind: 'FirstPartyInputsParsed'; inputs: FirstPartyInput[] } | { kind: 'FirstPartyInputsRejected'; message: string };
type FirstPartyInputNodeResult = { kind: 'FirstPartyInputAbsent'; token: boolean } | { kind: 'FirstPartyInputFound'; input: FirstPartyInput } | { kind: 'FirstPartyInputRejected'; message: string };
export type ProcessBoundary =
  | { kind: 'InheritProcess' | 'CompareProcess'; phase: string; argv: string[] }
  | { kind: 'CaptureProcess'; phase: string; argv: string[]; stdin: string; maxOutput: number }
  | { kind: 'CaptureToFileProcess'; phase: string; argv: string[]; stdin: string; maxOutput: number; outputPath: string };
export type RepoWorkflowPlan = { processes: ProcessBoundary[]; successOutput: string };
export type WatchOwnership = { timeoutSeconds: number; maxEvents: number };
type WorkflowCompletion = { kind: 'WorkflowSucceeded'; token: boolean } | { kind: 'WorkflowStopped'; phase: string; status: number; stdout: string; stderr: string };
type LintFingerprint = { path: string; digest: string };
type LintStampResult = { kind: 'LintStampParsed'; entries: LintFingerprint[] } | { kind: 'LintStampRejected'; line: number; message: string };
type DiffEntry =
  | { kind: 'DiffSame' | 'DiffMissing'; sourcePath: string; outputPath: string }
  | { kind: 'DiffDifferent'; sourcePath: string; outputPath: string; detail: string }
  | { kind: 'DiffErrored'; sourcePath: string; outputPath: string; message: string };
type DiffReport = { entries: DiffEntry[]; unchanged: number; different: number; errors: number; status: number };
type SchemaEntry = { name: string; typeName: string };
type SchemaTypeChange = { name: string; beforeType: string; afterType: string };
type SchemaDiff = { removed: SchemaEntry[]; added: SchemaEntry[]; typeChanged: SchemaTypeChange[] };
type OptionReference = { option: string; path: string };
type SchemaReference = { name: string; beforeType: string; afterType: string; paths: string[] };
type SchemaImpact = { diff: SchemaDiff; removedReferences: SchemaReference[]; typeChangedReferences: SchemaReference[] };
type WatchPlan = { kind: 'WatchIdle'; token: boolean } | { kind: 'WatchValidate'; paths: string[] };
type ArchitectureRow = { path: string; kind: string; source: string };
type ArchitectureSnapshot = { repo: string; configRoot: string; rows: ArchitectureRow[] };
type UpgradePhase = { kind: 'UpgradeSnapshot' | 'UpgradeLockUpdate' | 'UpgradeSchemaExtract' | 'UpgradeSchemaCompare' | 'UpgradeValidate'; token: boolean };
type UpgradePhaseResult = { phase: UpgradePhase; status: number };
type UpgradeFailure = { kind: 'UpgradeSucceeded'; token: boolean } | { kind: 'UpgradeStopped'; phase: UpgradePhase; status: number };

function jsonValueEnd(events: JsonEvent[], start: number): number {
  if (start < 0 || start >= events.length) return -1;
  const first = events[start];
  if (first.tag === 'JsonObjectStart' || first.tag === 'JsonArrayStart') {
    let depth = 0;
    const closing = first.tag === 'JsonObjectStart' ? 'JsonObjectEnd' : 'JsonArrayEnd';
    for (let index = start + 1; index < events.length; index++) {
      const tag = events[index].tag;
      if (tag === 'JsonObjectStart' || tag === 'JsonArrayStart') depth++;
      else if (tag === 'JsonObjectEnd' || tag === 'JsonArrayEnd') {
        if (tag === closing && depth === 0) return index + 1;
        depth--;
      }
    }
    return -1;
  }
  return ['JsonObjectEnd', 'JsonArrayEnd', 'JsonKey'].includes(first.tag) ? -1 : start + 1;
}

function jsonObjectFieldStart(events: JsonEvent[], objectStart: number, wanted: string): number {
  const end = jsonValueEnd(events, objectStart);
  if (end < 0 || events[objectStart].tag !== 'JsonObjectStart') return -1;
  let index = objectStart + 1;
  while (index < end - 1) {
    const key = events[index];
    if (key.tag !== 'JsonKey') return -1;
    const valueIndex = index + 1;
    const next = jsonValueEnd(events, valueIndex);
    if (next < 0) return -1;
    if (key.value === wanted) return valueIndex;
    index = next;
  }
  return -1;
}

function jsonObjectString(events: JsonEvent[], objectStart: number, wanted: string): string | null {
  const valueIndex = jsonObjectFieldStart(events, objectStart, wanted);
  if (valueIndex < 0) return null;
  const event = events[valueIndex];
  return event.tag === 'JsonString' ? event.value : null;
}

function jsonObject(events: JsonEvent[], start: number): boolean {
  return start >= 0 && start < events.length && events[start].tag === 'JsonObjectStart';
}

function firstPartyInputAt(events: JsonEvent[], name: string, nodeStart: number): FirstPartyInputNodeResult {
  const lockedStart = jsonObjectFieldStart(events, nodeStart, 'locked');
  const absent: FirstPartyInputNodeResult = { kind: 'FirstPartyInputAbsent', token: false };
  if (!jsonObject(events, lockedStart)) return absent;
  const sourceType = jsonObjectString(events, lockedStart, 'type');
  const owner = jsonObjectString(events, lockedStart, 'owner');
  const repo = jsonObjectString(events, lockedStart, 'repo');
  const rev = jsonObjectString(events, lockedStart, 'rev');
  const narHash = jsonObjectString(events, lockedStart, 'narHash');
  if (!(sourceType === 'github' && owner === 'tompassarelli')) return absent;
  const rejected = (message: string): FirstPartyInputNodeResult => ({ kind: 'FirstPartyInputRejected', message: `first-party input '${name}' ${message}` });
  if (repo === null || rev === null || narHash === null) return rejected('must have a complete GitHub owner/repo/rev/narHash lock');
  if (!safeComponent(repo)) return rejected('has an unsafe repository component');
  if (!pinnedRevision(rev)) return rejected('revision must be a full lowercase 40-hex commit');
  if (!pinnedNarHash(narHash)) return rejected('narHash has an invalid shape');
  return { kind: 'FirstPartyInputFound', input: { name, repo, rev } };
}

function firstPartyInputsFromLock(source: string): FirstPartyInputsResult {
  const decoded = decode(source);
  const rejected = (message: string): FirstPartyInputsResult => ({ kind: 'FirstPartyInputsRejected', message: `invalid flake.lock: ${message}` });
  if (decoded.tag === 'JsonDecodeError') return rejected(decoded.message);
  const { events } = decoded;
  if (events.length === 0 || jsonValueEnd(events, 0) !== events.length) return rejected('expected one JSON value');
  const nodesStart = jsonObjectFieldStart(events, 0, 'nodes');
  if (!jsonObject(events, nodesStart)) return rejected('missing nodes object');
  const rootStart = jsonObjectFieldStart(events, nodesStart, 'root');
  if (!jsonObject(events, rootStart)) return rejected('missing root node');
  const inputsStart = jsonObjectFieldStart(events, rootStart, 'inputs');
  if (!jsonObject(events, inputsStart)) return rejected('root inputs must be an object');
  const inputsEnd = jsonValueEnd(events, inputsStart);
  const inputs: FirstPartyInput[] = [];
  let index = inputsStart + 1;
  while (index < inputsEnd - 1) {
    const key = events[index];
    if (key.tag !== 'JsonKey') return rejected('invalid root inputs object');
    const valueStart = index + 1;
    const next = jsonValueEnd(events, valueStart);
    if (next < 0) return rejected('invalid root input value');
    const value = events[valueStart];
    if (value.tag === 'JsonString') {
      const nodeStart = jsonObjectFieldStart(events, nodesStart, value.value);
      if (nodeStart < 0) return rejected(`root input '${key.value}' points to a missing node`);
      const input = firstPartyInputAt(events, key.value, nodeStart);
      if (input.kind === 'FirstPartyInputRejected') return { kind: 'FirstPartyInputsRejected', message: input.message };
      if (input.kind === 'FirstPartyInputFound') inputs.push(input.input);
    }
    index = next;
  }
  return { kind: 'FirstPartyInputsParsed', inputs };
}

function charactersFrom(text: string, start: number, allowed: string): boolean {
  for (let index = start; index < text.length; index++) {
    if (!allowed.includes(text.substring(index, index + 1))) return false;
  }
  return true;
}

function safeComponent(value: string): boolean {
  return value.length > 0 && charactersFrom(value, 0, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-');
}

function pinnedRevision(value: string): boolean {
  return value.length === 40 && charactersFrom(value, 0, '0123456789abcdef');
}

function pinnedNarHash(value: string): boolean {
  return value.startsWith('sha256-') && value.length > 7 && charactersFrom(value, 7, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/=');
}

function trimLineEnd(text: string): string {
  let end = text.length;
  while (end > 0 && ['\n', '\r'].includes(text.substring(end - 1, end))) end--;
  return text.substring(0, end);
}

export function splitLines(text: string): string[] {
  if (text.length === 0) return [];
  const lines = text.split('\n');
  if (text.endsWith('\n')) lines.pop();
  return lines;
}

function joinLines(lines: string[]): string {
  return lines.map((line) => `${line}\n`).join('');
}

function appendUnique(values: string[], candidate: string): string[] {
  return values.includes(candidate) ? values : [...values, candidate];
}

export function parseRepoWorkflowArgv(argv: string[]): RepoWorkflowArgv {
  const invalid: RepoWorkflowArgv = { kind: 'InvalidRepoWorkflowArgv', argv };
  if (argv.length < 2 || argv[0] !== 'repo') return invalid;
  const edge = argv[1];
  const leafCount = argv.length - 2;
  const parsed = (action: RepoWorkflowAction): RepoWorkflowArgv => ({ kind: 'ParsedRepoWorkflow', action });
  switch (edge) {
    case 'validate':
    case 'lint':
    case 'doctor':
    case 'pin-ancestry':
    case 'watch': {
      if (!(leafCount === 0 || (leafCount === 1 && argv[2] === 'all'))) return invalid;
      const kinds = { validate: 'RepoValidate', lint: 'RepoLint', doctor: 'RepoDoctor', 'pin-ancestry': 'RepoPinAncestry', watch: 'RepoWatch' } as const;
      return parsed({ kind: kinds[edge], token: false });
    }
    case 'diff': return leafCount <= 1 ? parsed({ kind: 'RepoDiff', target: leafCount === 0 ? 'all' : argv[2] }) : invalid;
    case 'architecture':
      return leafCount === 0 || (leafCount === 1 && ['all', 'bundle', '--bundle'].includes(argv[2]))
        ? parsed({ kind: 'RepoArchitecture', bundle: leafCount === 1 && ['bundle', '--bundle'].includes(argv[2]) }) : invalid;
    case 'upgrade':
      return leafCount === 0 || (leafCount === 1 && ['now', 'dry-run'].includes(argv[2]))
        ? parsed({ kind: 'RepoUpgrade', dryRun: leafCount === 1 && argv[2] === 'dry-run' }) : invalid;
    default: return invalid;
  }
}

function nixTarget(path: string): boolean {
  const segments = quality.pathSegments(path);
  const basename = quality.pathBasename(segments);
  return path.endsWith('.nix') && basename !== 'hardware-configuration.nix'
    && !quality.stringMember(['.git', '.direnv', '.firn-cache', 'result'], basename)
    && !segments.some((segment, index) =>
      ['.git', '.direnv', '.firn-cache', '.firn-build'].includes(segment)
      || segment.startsWith('result')
      || (['docs', 'tests'].includes(segment) && segments[index + 1] === 'fixtures'));
}

function selectLintTargets(paths: string[]): string[] {
  return paths.filter(nixTarget).sort();
}

function parseLintStampLine(line: string, lineNumber: number): LintStampResult {
  const separator = line.indexOf('  ');
  if (separator <= 0 || separator + 2 >= line.length) return { kind: 'LintStampRejected', line: lineNumber, message: "expected '<digest>  <path>'" };
  return { kind: 'LintStampParsed', entries: [{ path: line.substring(separator + 2), digest: line.substring(0, separator) }] };
}

function parseLintStamp(text: string): LintStampResult {
  const lines = splitLines(text);
  const entries: LintFingerprint[] = [];
  for (let index = 0; index < lines.length; index++) {
    if (lines[index] === '') continue;
    const parsed = parseLintStampLine(lines[index], index + 1);
    if (parsed.kind === 'LintStampRejected') return parsed;
    entries.push(parsed.entries[0]);
  }
  return { kind: 'LintStampParsed', entries };
}

function renderLintStamp(entries: LintFingerprint[]): string {
  return entries.map((entry) => `${entry.digest}  ${entry.path}\n`).join('');
}

function findLintFingerprint(entries: LintFingerprint[], path: string): LintFingerprint | null {
  return entries.find((entry) => entry.path === path) ?? null;
}

function changedLintPaths(previous: LintFingerprint[], current: LintFingerprint[]): string[] {
  return current.filter((entry) => {
    const old = findLintFingerprint(previous, entry.path);
    return old === null || old.digest !== entry.digest;
  }).map((entry) => entry.path);
}

function lintSuccessText(total: number, changed: number): string {
  if (total === 0) return 'firn repo lint: no .nix files to lint.\n';
  if (changed === 0) return `firn repo lint: ${total} .nix files unchanged since their last clean parse.\n`;
  if (total === changed) return `firn repo lint: ${total} .nix files parse cleanly.\n`;
  return `firn repo lint: ${changed} changed of ${total} .nix files parse cleanly.\n`;
}

function diffEntryKind(entry: DiffEntry): string {
  switch (entry.kind) {
    case 'DiffSame': return 'same';
    case 'DiffDifferent':
    case 'DiffMissing': return 'different';
    case 'DiffErrored': return 'error';
  }
}

function summarizeDiff(entries: DiffEntry[]): DiffReport {
  let unchanged = 0;
  let different = 0;
  let errors = 0;
  for (const entry of entries) {
    const kind = diffEntryKind(entry);
    if (kind === 'same') unchanged++;
    else if (kind === 'different') different++;
    else errors++;
  }
  return { entries, unchanged, different, errors, status: different > 0 || errors > 0 ? 1 : 0 };
}

function renderDiffEntry(entry: DiffEntry): string {
  switch (entry.kind) {
    case 'DiffSame': return '';
    case 'DiffDifferent': return `=== ${entry.outputPath} ===\n${entry.detail}${entry.detail.endsWith('\n') ? '' : '\n'}`;
    case 'DiffMissing': return `=== ${entry.outputPath} ===\n(no committed .nix — would create)\n`;
    case 'DiffErrored': return `=== ${entry.outputPath} ===\n(error: ${trimLineEnd(entry.message)})\n`;
  }
}

function renderDiffReport(report: DiffReport): string {
  return report.entries.map(renderDiffEntry).join('') + `\nfirn diff: ${report.unchanged} unchanged, ${report.different} differ, ${report.errors} error(s)\n`;
}

function renderHealthEntry(entry: quality.HealthEntry): string {
  const mark = entry.kind === 'pass' ? '✓' : entry.kind === 'warning' ? '⚠' : '✗';
  return `  ${mark} ${entry.name}\n` + (entry.message === '' ? '' : splitLines(entry.message).map((line) => `      ${line}\n`).join(''));
}

function renderHealthReport(root: string, report: quality.HealthReport): string {
  return `firn doctor: running checks on ${root}\n\n` + report.entries.map(renderHealthEntry).join('')
    + `\nfirn doctor: ${report.passed} passed, ${report.warnings} warning(s), ${report.failed} failed.\n`;
}

type SchemaLookup = { kind: 'SchemaAbsent'; token: boolean } | { kind: 'SchemaFound'; entry: SchemaEntry };

function findSchemaEntry(entries: SchemaEntry[], name: string): SchemaLookup {
  const entry = entries.find((entry) => entry.name === name);
  return entry === undefined ? { kind: 'SchemaAbsent', token: false } : { kind: 'SchemaFound', entry };
}

function schemaNames(entries: SchemaEntry[]): string[] {
  return [...new Set(entries.map((entry) => entry.name))];
}

function schemaDiff(before: SchemaEntry[], after: SchemaEntry[]): SchemaDiff {
  const names = [...new Set([...schemaNames(before), ...schemaNames(after)])].sort();
  const removed: SchemaEntry[] = [];
  const added: SchemaEntry[] = [];
  const typeChanged: SchemaTypeChange[] = [];
  for (const name of names) {
    const old = findSchemaEntry(before, name);
    const next = findSchemaEntry(after, name);
    if (old.kind === 'SchemaAbsent') {
      if (next.kind === 'SchemaFound') added.push(next.entry);
    } else if (next.kind === 'SchemaAbsent') removed.push(old.entry);
    else if (old.entry.typeName !== next.entry.typeName) typeChanged.push({ name, beforeType: old.entry.typeName, afterType: next.entry.typeName });
  }
  return { removed, added, typeChanged };
}

function referenceLinePath(line: string): string {
  const start = line.startsWith('./') ? 2 : 0;
  const end = line.indexOf(':', start);
  return end < 0 ? '' : line.substring(start, end);
}

function parseOptionReferences(option: string, text: string): OptionReference[] {
  return splitLines(text).map(referenceLinePath).filter((path) => path !== '').map((path) => ({ option, path }));
}

function sourceReferencePaths(references: OptionReference[], name: string): string[] {
  return [...new Set(references.filter((reference) => reference.option === name).map((reference) => reference.path))];
}

function schemaImpact(diff: SchemaDiff, optionReferences: OptionReference[]): SchemaImpact {
  const removedReferences = diff.removed.map((entry) => ({ name: entry.name, beforeType: entry.typeName, afterType: '', paths: sourceReferencePaths(optionReferences, entry.name) })).filter((reference) => reference.paths.length > 0);
  const typeChangedReferences = diff.typeChanged.map((change) => ({ ...change, paths: sourceReferencePaths(optionReferences, change.name) })).filter((reference) => reference.paths.length > 0);
  return { diff, removedReferences, typeChangedReferences };
}

function renderReferencePaths(paths: string[]): string {
  return paths.map((path) => `      → ${path}\n`).join('');
}

function renderSchemaImpact(impact: SchemaImpact): string {
  const { diff, removedReferences: removed, typeChangedReferences: changed } = impact;
  const header = `  removed: ${diff.removed.length}   added: ${diff.added.length}   type-changed: ${diff.typeChanged.length}\n`;
  const removedText = removed.length === 0 ? '\n  ✓ no removed paths are referenced in this repo.\n'
    : `\n  ✗ ${removed.length} removed path(s) are referenced in this repo:\n` + removed.map((reference) => `    ${reference.name}\n${renderReferencePaths(reference.paths)}`).join('');
  const changedText = changed.length === 0 ? '' : `\n  ⚠ ${changed.length} type-changed path(s) referenced in this repo:\n`
    + changed.map((reference) => `    ${reference.name}: ${reference.beforeType} → ${reference.afterType}\n${renderReferencePaths(reference.paths)}`).join('');
  return header + removedText + changedText;
}

function planWatch(previous: LintFingerprint[], current: LintFingerprint[]): WatchPlan {
  const changed = changedLintPaths(previous, current);
  return changed.length === 0 ? { kind: 'WatchIdle', token: true } : { kind: 'WatchValidate', paths: changed };
}

function architecturePath(path: string): boolean {
  return path === 'AGENTS.md' || path.startsWith('dotfiles/agents/') || path.startsWith('modules/north-profile/');
}

function architectureRows(tracked: string[], kinds: string[]): ArchitectureRow[] {
  return tracked.flatMap((path, index) => architecturePath(path) ? [{ path, kind: index < kinds.length ? kinds[index] : 'unknown', source: `repo:${path}` }] : []);
}

function renderArchitecture(snapshot: ArchitectureSnapshot): string {
  return '# 02 · Local map — how THIS system is wired (GENERATED)\n\n'
    + '> GENERATED by `firn repo architecture` — do not hand-edit.\n'
    + '> The native command inventories the tracked configuration surface;\n'
    + '> a diff means the declared system moved.\n\n'
    + `Repo: \`${snapshot.repo}\` · agent config: \`${snapshot.configRoot}\`\n\n`
    + '## Declared configuration surface\n\n'
    + '| tracked path | kind | source-of-truth |\n|---|---|---|\n'
    + snapshot.rows.map((row) => `| \`${row.path}\` | ${row.kind} | \`${row.source}\` |\n`).join('')
    + `\nTracked architecture entries: ${snapshot.rows.length}\n`;
}

function upgradePhases(dryRun: boolean): UpgradePhase[] {
  const kinds: UpgradePhase['kind'][] = dryRun ? ['UpgradeLockUpdate', 'UpgradeSchemaExtract']
    : ['UpgradeSnapshot', 'UpgradeLockUpdate', 'UpgradeSchemaExtract', 'UpgradeSchemaCompare', 'UpgradeValidate'];
  return kinds.map((kind) => ({ kind, token: false }));
}

function phaseName(phase: UpgradePhase): string {
  return { UpgradeSnapshot: 'schema snapshot', UpgradeLockUpdate: 'nix flake update', UpgradeSchemaExtract: 'Galileo schema extraction', UpgradeSchemaCompare: 'schema comparison', UpgradeValidate: 'repository validation' }[phase.kind];
}

function firstUpgradeFailure(results: UpgradePhaseResult[]): UpgradeFailure {
  for (const result of results) {
    if (result.status !== 0) return { kind: 'UpgradeStopped', phase: result.phase, status: result.status };
  }
  return { kind: 'UpgradeSucceeded', token: false };
}

function renderUpgradeDryRun(): string {
  return '>> [dry-run] would run: nix flake update --flake <repo>\n'
    + '>> [dry-run] would run: galileo schema extract for NixOS\n'
    + 'firn upgrade: dry run complete; no files were changed.\n';
}

function rootPath(root: string, relative: string): string {
  return `${root}/${relative}`;
}

function lintProcesses(root: string, tracked: string[]): ProcessBoundary[] {
  const targets = selectLintTargets(tracked);
  return targets.length === 0 ? [] : [{ kind: 'InheritProcess', phase: 'lint', argv: ['nix-instantiate', '--parse', ...targets.map((path) => rootPath(root, path))] }];
}

function upgradeProcesses(root: string, dryRun: boolean): ProcessBoundary[] {
  if (dryRun) return [];
  return [
    { kind: 'InheritProcess', phase: 'current Galileo schema extraction', argv: ['env', `FIRN_REPO=${root}`, 'firn-schema', 'schema', 'extract'] },
    { kind: 'CaptureToFileProcess', phase: 'schema snapshot', argv: ['cat', rootPath(root, '.firn-cache/schema.json')], stdin: '', maxOutput: 67108864, outputPath: rootPath(root, '.firn-cache/schema.before.json') },
    { kind: 'InheritProcess', phase: 'nix flake update', argv: ['nix', 'flake', 'update', '--flake', root] },
    { kind: 'InheritProcess', phase: 'Galileo schema extraction', argv: ['env', `FIRN_REPO=${root}`, 'firn-schema', 'schema', 'extract'] },
    { kind: 'CompareProcess', phase: 'schema comparison', argv: ['diff', '--unified', rootPath(root, '.firn-cache/schema.before.json'), rootPath(root, '.firn-cache/schema.json')] },
    { kind: 'InheritProcess', phase: 'repository validation', argv: ['env', `FIRN_REPO=${root}`, 'firn-schema', 'repo', 'validate'] },
  ];
}

function watchProcesses(root: string, ownership: WatchOwnership): ProcessBoundary[] {
  return [
    { kind: 'InheritProcess', phase: 'watch for repository change', argv: ['timeout', '--foreground', String(ownership.timeoutSeconds), 'inotifywait', '--quiet', '--recursive', '--event', 'close_write,create,delete,move', '--include', '\\.gal$', root] },
    { kind: 'InheritProcess', phase: 'validate changed repository', argv: ['env', `FIRN_REPO=${root}`, 'firn-schema', 'repo', 'validate'] },
  ];
}

export function repoWorkflowPlan(root: string, action: RepoWorkflowAction, tracked: string[], ownership: WatchOwnership): RepoWorkflowPlan {
  switch (action.kind) {
    case 'RepoValidate':
    case 'RepoDoctor': return { processes: [{ kind: 'InheritProcess', phase: 'repository validation', argv: ['env', `FIRN_REPO=${root}`, 'firn-schema', 'repo', 'validate'] }], successOutput: '' };
    case 'RepoLint': return { processes: lintProcesses(root, tracked), successOutput: lintSuccessText(selectLintTargets(tracked).length, selectLintTargets(tracked).length) };
    case 'RepoDiff': return { processes: [{ kind: 'CaptureProcess', phase: 'repository diff', argv: ['firn-repo-build', 'repo', 'diff', action.target], stdin: '', maxOutput: 67108864 }], successOutput: '' };
    case 'RepoPinAncestry': return { processes: [], successOutput: '' };
    case 'RepoWatch': return { processes: watchProcesses(root, ownership), successOutput: '' };
    case 'RepoArchitecture': return { processes: [], successOutput: renderArchitecture({ repo: root, configRoot: rootPath(root, 'dotfiles/agents'), rows: architectureRows(tracked, []) }) };
    case 'RepoUpgrade': return { processes: upgradeProcesses(root, action.dryRun), successOutput: action.dryRun ? renderUpgradeDryRun() : '' };
  }
}

function firstProcessFailure(processes: ProcessBoundary[], observations: ProcessObservation[]): WorkflowCompletion {
  for (let index = 0; index < Math.min(processes.length, observations.length); index++) {
    const observation = observations[index];
    if (observation.status !== 0) return { kind: 'WorkflowStopped', phase: processes[index].phase, ...observation };
  }
  return { kind: 'WorkflowSucceeded', token: false };
}
