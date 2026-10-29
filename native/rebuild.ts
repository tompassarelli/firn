export interface Platform { name: string }
export interface Snapshot { root: string; revision: string; branch: string; uri: string }
export interface Target { firn: Snapshot; system: Snapshot; overridden: boolean }
export interface ArgvEffect { phase: string; argv: string[]; capture: boolean }
export interface TraceEvent { event: string; name: string; status: string; revision: string }
export interface Simulation { status: number; executed: ArgvEffect[]; events: TraceEvent[] }
export type PlatformResult = { tag: 'selected'; platform: Platform } | { tag: 'rejected'; name: string };
const captureEffect = (phase: string, argv: string[]): ArgvEffect => ({ phase, argv, capture: true });
const inheritEffect = (phase: string, argv: string[]): ArgvEffect => ({ phase, argv, capture: false });
export const snapshotUriFor = (root: string, revision: string, branch: string): string => `git+file://${root}?rev=${revision}${branch === '' ? '' : `&ref=${branch}`}`;
export const makeSnapshot = (root: string, revision: string, branch: string): Snapshot => ({ root, revision, branch, uri: snapshotUriFor(root, revision, branch) });
export const makeTarget = (firn: Snapshot): Target => ({ firn, system: firn, overridden: false });
export const makeSystemTarget = (firn: Snapshot, systemRoot: string, systemRevision: string): Target => ({ firn, system: makeSnapshot(systemRoot, systemRevision, ''), overridden: true });
const flakeRef = (target: Target, fragment: string): string => `${target.system.uri}#${fragment}`;
const withOverride = (argv: string[], target: Target): string[] => target.overridden ? [...argv, '--override-input', 'firn', target.firn.uri] : argv;
export const systemPinEffects = (root: string): ArgvEffect[] => [captureEffect('pin system flake revision', ['git', '-C', root, 'rev-parse', 'HEAD']), captureEffect('check system flake is clean', ['git', '-C', root, 'status', '--porcelain', '--untracked-files=no'])];
export function platformFromName(name: string): PlatformResult {
  return name === 'Linux' || name === 'Darwin' ? { tag: 'selected', platform: { name } } : { tag: 'rejected', name };
}
export const linuxPlatform = (): Platform => ({ name: 'Linux' });
export const darwinPlatform = (): Platform => ({ name: 'Darwin' });
export const linux = (platform: Platform): boolean => platform.name === 'Linux';
export const platformEffect = (): ArgvEffect => captureEffect('select platform', ['uname', '-s']);
export const pinEffects = (root: string): ArgvEffect[] => [captureEffect('pin revision', ['git', '-C', root, 'rev-parse', 'HEAD']), captureEffect('pin branch', ['git', '-C', root, 'branch', '--show-current']), platformEffect()];
export function preparationEffects(target: Target, host: string, platform: Platform, snapshotDirectory: string): ArgvEffect[] {
  const snapshot = target.firn;
  return [
    captureEffect('pin committed snapshot', ['git', '-C', snapshot.root, 'cat-file', '-e', `${snapshot.revision}^{commit}`]),
    captureEffect('materialize committed snapshot', ['git', '-C', snapshot.root, 'worktree', 'add', '--detach', snapshotDirectory, snapshot.revision]),
    inheritEffect('validate committed snapshot', ['env', `FIRN_REPO=${snapshotDirectory}`, 'firn', 'repo', 'validate']),
    captureEffect('retire validation snapshot', ['git', '-C', snapshot.root, 'worktree', 'remove', '--force', snapshotDirectory]),
    captureEffect('build committed snapshot', withOverride(['nix', 'build', '--no-link', '--print-out-paths', flakeRef(target, linux(platform) ? `nixosConfigurations.${host}.config.system.build.toplevel` : `darwinConfigurations.${host}.system`)], target)),
  ];
}
export const activateVerifiedClosureEffect = (builtPath: string): ArgvEffect => inheritEffect('activate verified closure', ['sudo', `${builtPath}/bin/switch-to-configuration`, 'switch']);
export function activationEffects(target: Target, host: string, platform: Platform, builtPath: string): ArgvEffect[] {
  const preflight = inheritEffect('activation preflight', ['sudo', '-v']);
  return linux(platform) ? [preflight, inheritEffect('activate system profile', ['sudo', 'nix-env', '--profile', '/nix/var/nix/profiles/system', '--set', builtPath]), activateVerifiedClosureEffect(builtPath)] : [preflight, inheritEffect('activate verified closure', withOverride(['sudo', 'darwin-rebuild', 'switch', '--flake', flakeRef(target, host)], target))];
}
export const exactPathProfileEffects = (builtPath: string): ArgvEffect[] => [inheritEffect('activation preflight', ['sudo', '-v']), inheritEffect('select persistent system profile', ['sudo', 'nix-env', '--profile', '/nix/var/nix/profiles/system', '--set', builtPath])];
export const systemProfileResolveEffect = (): ArgvEffect => captureEffect('verify persistent system profile', ['readlink', '-e', '/nix/var/nix/profiles/system']);
export const generationQueryEffect = (platform: Platform): ArgvEffect => captureEffect('read active generation', linux(platform) ? ['nixos-rebuild', 'list-generations'] : ['darwin-rebuild', '--list-generations']);
export const generationResolveEffect = (generation: string): ArgvEffect => captureEffect('resolve rollback generation', ['readlink', '-e', `/nix/var/nix/profiles/system-${generation}-link`]);
export const generationClosureCheckEffect = (builtPath: string): ArgvEffect => captureEffect('validate rollback closure', ['test', '-x', `${builtPath}/bin/switch-to-configuration`]);
export const rollbackActivationEffects = (generation: string, builtPath: string): ArgvEffect[] => [inheritEffect('activation preflight', ['sudo', '-v']), inheritEffect('select rollback generation', ['sudo', 'nix-env', '--profile', '/nix/var/nix/profiles/system', '--switch-generation', generation]), activateVerifiedClosureEffect(builtPath)];
const tagEffect = (phase: string, snapshot: Snapshot, generation: string): ArgvEffect => captureEffect(phase, ['git', '-C', snapshot.root, 'tag', '-f', `gen-${generation}`, snapshot.revision]);
export function generationTagEffects(target: Target, generation: string): ArgvEffect[] {
  const firnTag = tagEffect('tag active generation', target.firn, generation);
  return target.overridden ? [firnTag, tagEffect('tag active generation in system flake', target.system, generation)] : [firnTag];
}
export const environmentQueryEffect = (target: Target, host: string): ArgvEffect => captureEffect('query user environment', ['nix', 'eval', '--json', `${target.firn.uri}#packages`, '--apply', `packages: builtins.any (system: (builtins.getAttr system packages) ? "${host}-environment") (builtins.attrNames packages)`]);
export const environmentPresent = (text: string): boolean => text.trim() === 'true';
export const environmentSwitchEffect = (target: Target, host: string): ArgvEffect => inheritEffect('switch user environment', ['firn-environment-switch', host, target.firn.uri]);
export const advisoryEffect = (snapshot: Snapshot): ArgvEffect => inheritEffect('schedule agent configuration check', ['systemd-run', '--user', '--no-block', '--collect', '--quiet', '--unit', `firn-agent-config-check-${snapshot.revision}.service`, '--description', 'Firn agent configuration advisory check', '--property=Type=oneshot', 'bash', '-c', 'exec "$HOME/.local/bin/north" agent-config-check --local']);
export const storePath = (text: string): boolean => text.trim().startsWith('/nix/store/');
const decimalString = (text: string): boolean => text.length > 0 && [...text].every(character => '0123456789'.includes(character));
export const generationToken = (text: string): boolean => decimalString(text) && text[0] !== '0';
export function generationLess(left: string, right: string): boolean {
  if (left.length !== right.length) return left.length < right.length;
  for (let index = 0; index < left.length; index++) {
    const leftDigit = '0123456789'.indexOf(left[index]), rightDigit = '0123456789'.indexOf(right[index]);
    if (leftDigit !== rightDigit) return leftDigit < rightDigit;
  }
  return false;
}
const firstToken = (line: string): string => line.trim().split(/[ \t]/, 1)[0];
const splitLines = (text: string): string[] => text === '' ? [] : text.endsWith('\n') ? text.slice(0, -1).split('\n') : text.split('\n');
export function currentGeneration(text: string): string | null {
  for (const line of splitLines(text)) {
    const generation = firstToken(line);
    if ((line.includes('True') || line.toLowerCase().includes('current')) && decimalString(generation)) return generation;
  }
  return null;
}
export const generationPresent = (text: string, generation: string): boolean => splitLines(text).some(line => firstToken(line) === generation);
export const exactStorePath = (text: string): boolean => storePath(text) && !/[\n\r\t ]/.test(text.trim());
export const startEvent = (effect: ArgvEffect, revision: string): TraceEvent => ({ event: 'span_start', name: effect.phase, status: 'started', revision });
export const endEvent = (effect: ArgvEffect, revision: string, status: number): TraceEvent => ({ event: 'span_end', name: effect.phase, status: status === 0 ? 'ok' : 'error', revision });
export function simulate(effects: ArgvEffect[], statuses: number[], revision: string): Simulation {
  const executed: ArgvEffect[] = [], events: TraceEvent[] = [];
  for (let index = 0; index < effects.length; index++) {
    if (index >= statuses.length) return { status: 70, executed, events };
    const effect = effects[index], status = statuses[index];
    executed.push(effect);
    events.push(startEvent(effect, revision), endEvent(effect, revision, status));
    if (status !== 0) return { status, executed, events };
  }
  return { status: 0, executed, events };
}
export const effectPhases = (effects: ArgvEffect[]): string[] => effects.map(effect => effect.phase);
