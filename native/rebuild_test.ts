import * as r from './rebuild.ts';
const revision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
function target(overridden: boolean): r.Target {
  const snapshot = r.makeSnapshot('/repo', revision, 'native-rebuild-workflow');
  return overridden ? r.makeSystemTarget(snapshot, '/system', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb') : r.makeTarget(snapshot);
}
function plan(platform: r.Platform, overridden: boolean, mode: number): r.ArgvEffect[] {
  const value = target(overridden), path = '/nix/store/system';
  if (mode === 1) return [...r.exactPathProfileEffects(path), r.systemProfileResolveEffect(), r.activateVerifiedClosureEffect(path)];
  if (mode === 2) return [r.generationResolveEffect('40'), r.generationClosureCheckEffect(path), ...r.rollbackActivationEffects('40', path)];
  return [...r.preparationEffects(value, 'fixture', platform, '/snapshot'), ...r.activationEffects(value, 'fixture', platform, path), r.generationQueryEffect(platform), ...r.generationTagEffects(value, '42')];
}
const tokenCount = (values: string[], value: string): number => values.filter(token => token === value).length;
const same = (left: unknown, right: unknown): boolean => JSON.stringify(left) === JSON.stringify(right);
function operation(argv: string[]): string {
  const text = argv.join(',');
  if (tokenCount(argv, 'cat-file') > 0) return 'pin committed snapshot';
  if (tokenCount(argv, 'worktree') > 0 && tokenCount(argv, 'add') > 0) return 'materialize committed snapshot';
  if (tokenCount(argv, 'validate') > 0) return 'validate committed snapshot';
  if (tokenCount(argv, 'worktree') > 0 && tokenCount(argv, 'remove') > 0) return 'retire validation snapshot';
  if (argv[0] === 'nix' && tokenCount(argv, 'build') > 0) return 'build committed snapshot';
  if (same(argv, ['sudo', '-v'])) return 'activation preflight';
  if (tokenCount(argv, '--set') > 0) return 'select system profile';
  if (tokenCount(argv, '--switch-generation') > 0) return 'select rollback generation';
  if (argv[0] === 'sudo' && tokenCount(argv, 'switch') > 0) return 'activate verified closure';
  if (tokenCount(argv, 'list-generations') > 0 || tokenCount(argv, '--list-generations') > 0) return 'read active generation';
  if (tokenCount(argv, 'tag') > 0) return 'tag active generation';
  if (argv[0] === 'readlink') return text.includes('system-') ? 'resolve rollback generation' : 'verify persistent system profile';
  if (argv[0] === 'test') return 'validate rollback closure';
  return 'unknown';
}
const phaseIndex = (effects: r.ArgvEffect[], phase: string): number => effects.findIndex(effect => operation(effect.argv) === phase);
const ordered = (effects: r.ArgvEffect[], before: string, after: string): boolean => phaseIndex(effects, before) >= 0 && phaseIndex(effects, after) > phaseIndex(effects, before);
function orderRule(effects: r.ArgvEffect[], linux: boolean, mode: number): boolean {
  if (mode === 1) return ordered(effects, 'activation preflight', 'select system profile') && ordered(effects, 'select system profile', 'verify persistent system profile') && ordered(effects, 'verify persistent system profile', 'activate verified closure');
  if (mode === 2) return ordered(effects, 'resolve rollback generation', 'validate rollback closure') && ordered(effects, 'validate rollback closure', 'activation preflight') && ordered(effects, 'activation preflight', 'select rollback generation') && ordered(effects, 'select rollback generation', 'activate verified closure');
  return ordered(effects, 'pin committed snapshot', 'materialize committed snapshot') && ordered(effects, 'materialize committed snapshot', 'validate committed snapshot') && ordered(effects, 'validate committed snapshot', 'retire validation snapshot') && ordered(effects, 'retire validation snapshot', 'build committed snapshot') && ordered(effects, 'build committed snapshot', 'activation preflight') && ordered(effects, 'activation preflight', 'activate verified closure') && (!linux || (ordered(effects, 'activation preflight', 'select system profile') && ordered(effects, 'select system profile', 'activate verified closure'))) && ordered(effects, 'activate verified closure', 'read active generation') && ordered(effects, 'read active generation', 'tag active generation');
}
function platformRule(effects: r.ArgvEffect[], linux: boolean, overridden: boolean, mode: number): boolean {
  for (const effect of effects) {
    const argv = effect.argv, phase = operation(argv), text = argv.join(',');
    if (linux ? text.includes('darwin-rebuild') : text.includes('nix-env') || text.includes('switch-to-configuration')) return false;
    if (phase === 'build committed snapshot' && !(tokenCount(argv, '--override-input') === (overridden ? 1 : 0) && argv[4] === `${overridden ? 'git+file:///system?rev=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' : `git+file:///repo?rev=${revision}&ref=native-rebuild-workflow`}${linux ? '#nixosConfigurations.fixture.config.system.build.toplevel' : '#darwinConfigurations.fixture.system'}`)) return false;
    if (phase === 'select system profile' && !same(argv, ['sudo', 'nix-env', '--profile', '/nix/var/nix/profiles/system', '--set', '/nix/store/system'])) return false;
    if (linux && phase === 'activate verified closure' && !same(argv, ['sudo', '/nix/store/system/bin/switch-to-configuration', 'switch'])) return false;
    if (phase === 'select rollback generation' && !same(argv, ['sudo', 'nix-env', '--profile', '/nix/var/nix/profiles/system', '--switch-generation', '40'])) return false;
  }
  return true;
}
function statuses(length: number, failure: number, seed: number): number[] {
  return Array.from({ length }, (_, index) => index === failure || index === failure + 2 ? 1 + (seed + index) % 63 : 0);
}
function simulationRule(effects: r.ArgvEffect[], codes: number[]): boolean {
  const result = r.simulate(effects, codes, revision);
  let expectedLength = 0;
  while (expectedLength < effects.length && expectedLength < codes.length) { const status = codes[expectedLength++]; if (status !== 0) break; }
  const expectedStatus = expectedLength > 0 && codes[expectedLength - 1] !== 0 ? codes[expectedLength - 1] : expectedLength < effects.length ? 70 : 0;
  const { executed, events } = result;
  if (result.status !== expectedStatus || executed.length !== expectedLength || events.length !== 2 * expectedLength) return false;
  for (let index = 0; index < expectedLength; index++) {
    const effect = effects[index], start = events[2 * index], end = events[2 * index + 1];
    if (!(same(executed[index], effect) && start.event === 'span_start' && start.status === 'started' && end.event === 'span_end' && end.status === (codes[index] === 0 ? 'ok' : 'error') && start.name === effect.phase && end.name === effect.phase && start.revision === revision && end.revision === revision)) return false;
  }
  return true;
}
function generatedWorkflow(seed: number, variant: number): boolean {
  const linux = variant !== 2, overridden = seed % 2 === 1, mode = variant === 3 ? 1 : variant === 4 ? 2 : 0;
  const effects = plan(linux ? r.linuxPlatform() : r.darwinPlatform(), overridden, mode);
  if (!orderRule(effects, linux, mode) || !platformRule(effects, linux, overridden, mode)) return false;
  for (let index = -1; index < effects.length; index++) if (!simulationRule(effects, statuses(effects.length, index, seed)) || !simulationRule(effects, statuses(index + 1, -3, seed))) return false;
  return true;
}
function inputRules(seed: number): boolean {
  const generation = String(1 + seed % 1000), next = String(2 + seed % 1000), listing = `${generation} date\n${next} date True\n`;
  return r.generationToken(generation) && !r.generationToken(`0${generation}`) && !r.generationToken('latest') && !r.generationToken('0') && !r.generationToken('') && r.generationPresent(listing, generation) && !r.generationPresent(listing, '99999') && r.generationLess('999', '1000') && r.generationLess(generation, next) && !r.generationLess(next, generation) && !r.generationLess(generation, generation) && r.currentGeneration(listing) === next && r.currentGeneration(`${generation} date\n${next} date current\n`) === next && r.storePath(' /nix/store/system\n') && !r.storePath('warning only\n') && r.exactStorePath('/nix/store/system') && !r.exactStorePath('relative-system') && !r.exactStorePath('/nix/store/one\n/nix/store/two');
}
export function runProperties(samples: number): number {
  if (samples <= 0) return 1;
  let seed = 73421;
  for (let index = 0; index < samples; index++) {
    let passed = inputRules(seed);
    if (passed) {
      for (let variant = 0; variant < 5; variant++) {
        if (!generatedWorkflow(seed + variant, variant)) { console.log(`FAIL rebuild seed=${seed} variant=${variant}`); passed = false; break; }
      }
    }
    if (!passed) { console.log(`FAIL rebuild order/prefix seed=${seed} case=${index}`); return 1; }
    seed = seed * 48271 % 2147483647;
  }
  return 0;
}
