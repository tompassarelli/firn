import * as views from './firn_views.ts';

const suffix = (seed: number): string => seed === 0 ? '' : String(seed);
const row = views.platformRow;
const verdict = (verdicts: views.PlatformVerdict[], name: string): string => views.verdictFor(verdicts, name)?.verdict ?? 'missing';

function casePlatformVerdicts(seed: number): boolean {
  const both = 'both' + suffix(seed);
  const linux = 'linux' + suffix(seed);
  const darwin = 'darwin' + suffix(seed);
  const neither = 'neither' + suffix(seed);
  const everywhere = views.platformMatrix([both, linux], [row(both, 'linux'), row(linux, 'linux'), row(both, 'darwin')]);
  const nowhere = views.platformMatrix([darwin, neither], [row(darwin, 'darwin')]);
  return verdict(everywhere, both) === 'both' && verdict(everywhere, linux) === 'linux-only'
    && verdict(nowhere, darwin) === 'darwin-only' && verdict(nowhere, neither) === 'neither';
}

function actionKind(seed: number, action: views.ViewsAction): string {
  switch (action._tag) {
    case 'FlakeInputs': return 'flake';
    case 'PlatformList': return 'platform-list';
    case 'PlatformShow': return 'platform-show';
    case 'PlatformSafelist': return 'platform-safelist';
    case 'SchemaExplain': return 'schema-explain';
    case 'HostGeneration': return 'host-gen:' + action.host;
  }
}

function parsedKind(seed: number, argv: string[]): string {
  const parsed = views.parseViewsArgv(argv, 'host-a' + suffix(seed));
  return parsed._tag === 'InvalidViewsArgv' ? 'invalid' : actionKind(seed, parsed.action);
}

function caseArgv(seed: number): boolean {
  return parsedKind(seed, ['flake', 'inputs']) === 'flake'
    && parsedKind(seed, ['platform', 'list', 'all']) === 'platform-list'
    && parsedKind(seed, ['platform', 'show', 'linux' + suffix(seed)]) === 'platform-show'
    && parsedKind(seed, ['platform', 'safelist', 'all']) === 'platform-safelist'
    && parsedKind(seed, ['schema', 'explain', 'services.mode' + suffix(seed)]) === 'schema-explain'
    && parsedKind(seed, ['schema', 'extract']) === 'invalid'
    && parsedKind(seed, ['host', 'gen']) === 'host-gen:host-a' + suffix(seed)
    && parsedKind(seed, ['stale']) === 'invalid';
}

function childConservation(seed: number): boolean {
  const status = 1 + seed % 127;
  const out = 'output-' + seed;
  const err = 'error-' + seed;
  const failed = views.renderHostGeneration(views.childResult(status, out, err));
  return failed.status === status && views.startsWith(failed.stderr, err);
}

export function runScenarios(): number {
  if (casePlatformVerdicts(0) && caseArgv(0)) return 0;
  console.log('FAIL views scenarios');
  return 1;
}

export function runProperties(samples: number): number {
  if (samples <= 0) return 1;
  let seed = 73421;
  for (let index = 0; index < samples; index++) {
    if (!childConservation(seed)) {
      console.log(`FAIL child conservation seed=${seed}`);
      return 1;
    }
    seed = seed * 48271 % 2147483647;
  }
  return 0;
}
