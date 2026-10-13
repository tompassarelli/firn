type OutputMetadata = { sourcePath: string; outputPath: string; outputPresent: boolean; sourceRevision: number; outputRevision: number };
type OutputFreshness =
  | { kind: 'OutputMissing'; sourcePath: string; outputPath: string }
  | { kind: 'OutputStale'; sourcePath: string; outputPath: string; sourceRevision: number; outputRevision: number }
  | { kind: 'OutputCurrent'; sourcePath: string; outputPath: string };
type HealthResult =
  | { kind: 'HealthPassed'; name: string }
  | { kind: 'HealthFailed' | 'HealthWarned'; name: string; message: string };
type HealthInputs = { f0: HealthResult[]; f1: HealthResult[]; f4: HealthResult[] };
export type HealthEntry = { source: string; kind: string; name: string; message: string };
export type HealthReport = { entries: HealthEntry[]; passed: number; failed: number; warnings: number; status: number };

export function pathSegments(path: string): string[] {
  return path.split('/');
}

export function stringMember(values: string[], candidate: string): boolean {
  return values.includes(candidate);
}

function excludedQualityPath(segments: string[]): boolean {
  return segments.some((segment, index) =>
    ['', '.', '..', '.git', '.direnv', '.firn-build', 'result', 'scripts', 'tests'].includes(segment)
    || (segment === 'docs' && segments[index + 1] === 'fixtures'));
}

export function pathBasename(segments: string[]): string {
  return segments.at(-1) ?? '';
}

function qualityTarget(path: string): boolean {
  return path.endsWith('.gal') && !excludedQualityPath(pathSegments(path));
}

function selectQualityTargets(paths: string[]): string[] {
  return paths.filter(qualityTarget).sort();
}

function classifyOutput(metadata: OutputMetadata): OutputFreshness {
  const { sourcePath, outputPath, sourceRevision, outputRevision } = metadata;
  if (!metadata.outputPresent) return { kind: 'OutputMissing', sourcePath, outputPath };
  if (outputRevision < sourceRevision) return { kind: 'OutputStale', sourcePath, outputPath, sourceRevision, outputRevision };
  return { kind: 'OutputCurrent', sourcePath, outputPath };
}

function healthEntry(source: string, result: HealthResult): HealthEntry {
  switch (result.kind) {
    case 'HealthPassed': return { source, kind: 'pass', name: result.name, message: '' };
    case 'HealthFailed': return { source, kind: 'failure', name: result.name, message: result.message };
    case 'HealthWarned': return { source, kind: 'warning', name: result.name, message: result.message };
  }
}

function orderedHealthEntries(inputs: HealthInputs): HealthEntry[] {
  return [
    ...inputs.f0.map((result) => healthEntry('f0', result)),
    ...inputs.f1.map((result) => healthEntry('f1', result)),
    ...inputs.f4.map((result) => healthEntry('f4', result)),
  ];
}

function aggregateHealth(inputs: HealthInputs): HealthReport {
  const entries = orderedHealthEntries(inputs);
  let passed = 0;
  let failed = 0;
  let warnings = 0;
  for (const entry of entries) {
    if (entry.kind === 'pass') passed++;
    else if (entry.kind === 'failure') failed++;
    else warnings++;
  }
  return { entries, passed, failed, warnings, status: failed > 0 ? 1 : 0 };
}
