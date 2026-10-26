import * as r from './rebuild.ts';
import { encode, type JsonEvent } from './native_json.ts';

declare global {
  var firn_host_env: (name: string) => string | null;
  var firn_host_pid: () => number;
  var firn_host_out: (text: string) => unknown;
  var firn_host_err: (text: string) => unknown;
  var firn_host_capture: (argv: string[], limit: number) => ['ok', number, string, string] | ['error', number];
  var firn_host_inherit: (argv: string[]) => number;
  var firn_host_append: (path: string, text: string) => ['ok'] | ['error', number];
  var firn_host_git_checkout: (path: string) => boolean;
}
const maxCommandOutput = 16777216;
type EffectResult = { tag: 'succeeded'; stdout: string } | { tag: 'failed'; status: number };
type SnapshotResult = { tag: 'pinned'; snapshot: r.Snapshot } | { tag: 'failed'; status: number };
type TargetResult = { tag: 'pinned'; target: r.Target } | { tag: 'failed'; status: number };
const stderrLine = (text: string): void => { globalThis.firn_host_err(`${text}\n`); };
function appendTrace(tracePath: string | null, traceId: string, event: r.TraceEvent): boolean {
  if (tracePath === null) return true;
  const events: JsonEvent[] = [{ tag: 'JsonObjectStart', offset: 0 }];
  for (const [key, value] of [['schema', 'firn.rebuild/v1'], ['trace_id', traceId], ['event', event.event], ['name', event.name], ['status', event.status], ['revision', event.revision]]) {
    events.push({ tag: 'JsonKey', offset: 0, value: key }, { tag: 'JsonString', offset: 0, value });
  }
  events.push({ tag: 'JsonObjectEnd', offset: 0 });
  const encoded = encode(events);
  if (encoded.tag === 'JsonEncodeError') {
    stderrLine(`firn rebuild: trace encoding failed at event ${encoded.eventIndex}: ${encoded.message}`);
    return false;
  }
  const result = globalThis.firn_host_append(tracePath, `${encoded.text}\n`);
  if (result[0] === 'ok') return true;
  stderrLine(`firn rebuild: cannot append trace: errno ${result[1]}`);
  return false;
}
function finishEffect(effect: r.ArgvEffect, tracePath: string | null, traceId: string, revision: string, status: number, stdout: string): EffectResult {
  if (!appendTrace(tracePath, traceId, r.endEvent(effect, revision, status))) return { tag: 'failed', status: 74 };
  return status === 0 ? { tag: 'succeeded', stdout } : { tag: 'failed', status };
}
function executeEffect(effect: r.ArgvEffect, tracePath: string | null, traceId: string, revision: string): EffectResult {
  if (!appendTrace(tracePath, traceId, r.startEvent(effect, revision))) return { tag: 'failed', status: 74 };
  if (effect.capture) {
    const result = globalThis.firn_host_capture(effect.argv, maxCommandOutput);
    if (result[0] === 'error') {
      stderrLine(`firn rebuild: cannot start ${effect.phase}: errno ${result[1]}`);
      return finishEffect(effect, tracePath, traceId, revision, 126, '');
    }
    const [, status, stdout, stderr] = result;
    if (stdout !== '') globalThis.firn_host_out(stdout);
    if (stderr !== '') globalThis.firn_host_err(stderr);
    return finishEffect(effect, tracePath, traceId, revision, status, stdout);
  }
  return finishEffect(effect, tracePath, traceId, revision, globalThis.firn_host_inherit(effect.argv), '');
}
function executeEffects(effects: r.ArgvEffect[], tracePath: string | null, traceId: string, revision: string): EffectResult {
  let lastStdout = '';
  for (const effect of effects) {
    const result = executeEffect(effect, tracePath, traceId, revision);
    if (result.tag === 'failed') return result;
    if (result.stdout !== '') lastStdout = result.stdout;
  }
  return { tag: 'succeeded', stdout: lastStdout };
}
function pinSnapshot(root: string, tracePath: string | null, traceId: string): SnapshotResult {
  const effects = r.pinEffects(root);
  const pinned = executeEffect(effects[0], tracePath, traceId, '');
  if (pinned.tag === 'failed') return pinned;
  const revision = pinned.stdout.trim();
  if (revision === '') { stderrLine('firn rebuild: git returned an empty revision'); return { tag: 'failed', status: 65 }; }
  const branch = executeEffect(effects[1], tracePath, traceId, revision);
  return branch.tag === 'failed' ? branch : { tag: 'pinned', snapshot: r.makeSnapshot(root, revision, branch.stdout.trim()) };
}
function selectPlatform(revision: string, tracePath: string | null, traceId: string): r.PlatformResult {
  const result = executeEffect(r.platformEffect(), tracePath, traceId, revision);
  return result.tag === 'failed' ? { tag: 'rejected', name: String(result.status) } : r.platformFromName(result.stdout.trim());
}
function failPhase(status: number): number { stderrLine(`firn rebuild: stopped at first failure (status ${status})`); return status; }
const targetRevision = (target: r.Target): string => target.firn.revision;
function runAdvisory(target: r.Target, platform: r.Platform, tracePath: string | null, traceId: string): number {
  if (!r.linux(platform)) return 0;
  const result = executeEffect(r.advisoryEffect(target.firn), tracePath, traceId, targetRevision(target));
  return result.tag === 'failed' ? failPhase(result.status) : 0;
}
function applyEnvironment(target: r.Target, host: string, platform: r.Platform, tracePath: string | null, traceId: string): number {
  globalThis.firn_host_out(`firn rebuild: switching user environment ${host}-environment\n`);
  const result = executeEffect(r.environmentSwitchEffect(target, host), tracePath, traceId, targetRevision(target));
  return result.tag === 'failed' ? failPhase(result.status) : runAdvisory(target, platform, tracePath, traceId);
}
function switchEnvironment(target: r.Target, host: string, platform: r.Platform, tracePath: string | null, traceId: string): number {
  if (r.linux(platform)) {
    const result = executeEffect(r.environmentQueryEffect(target, host), tracePath, traceId, targetRevision(target));
    if (result.tag === 'failed') return failPhase(result.status);
    if (r.environmentPresent(result.stdout)) return applyEnvironment(target, host, platform, tracePath, traceId);
  }
  return runAdvisory(target, platform, tracePath, traceId);
}
function recordGeneration(target: r.Target, platform: r.Platform, tracePath: string | null, traceId: string): number {
  const queried = executeEffect(r.generationQueryEffect(platform), tracePath, traceId, targetRevision(target));
  if (queried.tag === 'failed') return failPhase(queried.status);
  const generation = r.currentGeneration(queried.stdout);
  if (generation === null) { stderrLine('firn rebuild: active generation was not reported'); return 65; }
  const tagged = executeEffects(r.generationTagEffects(target, generation), tracePath, traceId, targetRevision(target));
  return tagged.tag === 'failed' ? failPhase(tagged.status) : 0;
}
function tagGeneration(target: r.Target, host: string, platform: r.Platform, tracePath: string | null, traceId: string): number {
  const recorded = recordGeneration(target, platform, tracePath, traceId);
  return recorded === 0 ? switchEnvironment(target, host, platform, tracePath, traceId) : recorded;
}
function activate(target: r.Target, host: string, platform: r.Platform, builtPath: string, tracePath: string | null, traceId: string): number {
  const effects = r.activationEffects(target, host, platform, builtPath);
  const selected = executeEffects(effects.slice(0, -1), tracePath, traceId, targetRevision(target));
  if (selected.tag === 'failed') return failPhase(selected.status);
  const switched = executeEffect(effects[effects.length - 1], tracePath, traceId, targetRevision(target));
  if (switched.tag === 'succeeded') return tagGeneration(target, host, platform, tracePath, traceId);
  if (r.linux(platform)) recordGeneration(target, platform, tracePath, traceId);
  return failPhase(switched.status);
}
function switchExactPath(builtPath: string, tracePath: string | null, traceId: string): number {
  const result = executeEffect(r.activateVerifiedClosureEffect(builtPath), tracePath, traceId, builtPath);
  if (result.tag === 'failed') {
    stderrLine(`firn activate: persistent system profile is ${builtPath}, but configuration switching failed (status ${result.status}); running and boot state may be incomplete`);
    return result.status;
  }
  globalThis.firn_host_out(`firn activate: activated ${builtPath}\n`);
  return 0;
}
function verifyExactSystemProfile(builtPath: string, tracePath: string | null, traceId: string): number {
  const result = executeEffect(r.systemProfileResolveEffect(), tracePath, traceId, builtPath);
  if (result.tag === 'failed') {
    stderrLine(`firn activate: persistent system profile could not be verified after selection (status ${result.status}); no configuration switch was attempted`);
    return result.status;
  }
  const profilePath = result.stdout.trim();
  if (profilePath === builtPath) return switchExactPath(builtPath, tracePath, traceId);
  stderrLine(`firn activate: persistent system profile resolved to ${profilePath} instead of ${builtPath}; no configuration switch was attempted`);
  return 65;
}
function persistExactSystemProfile(builtPath: string, tracePath: string | null, traceId: string): number {
  const result = executeEffects(r.exactPathProfileEffects(builtPath), tracePath, traceId, builtPath);
  if (result.tag === 'failed') {
    stderrLine(`firn activate: persistent system profile selection failed (status ${result.status}); verify /nix/var/nix/profiles/system before retrying`);
    return result.status;
  }
  return verifyExactSystemProfile(builtPath, tracePath, traceId);
}
function activateExactPath(builtPath: string, tracePath: string | null, traceId: string): number {
  if (!r.exactStorePath(builtPath)) { stderrLine('firn activate: target must be one exact /nix/store toplevel path'); return 64; }
  const result = executeEffect(r.generationClosureCheckEffect(builtPath), tracePath, traceId, builtPath);
  if (result.tag === 'failed') {
    stderrLine(`firn activate: target does not contain an executable switch-to-configuration (status ${result.status}); no activation was attempted`);
    return result.status;
  }
  return persistExactSystemProfile(builtPath, tracePath, traceId);
}
function pinTarget(snapshot: r.Snapshot, systemRoot: string | null, tracePath: string | null, traceId: string): TargetResult {
  if (systemRoot === null) return { tag: 'pinned', target: r.makeTarget(snapshot) };
  const effects = r.systemPinEffects(systemRoot), revision = snapshot.revision;
  const pinned = executeEffect(effects[0], tracePath, traceId, revision);
  if (pinned.tag === 'failed') return pinned;
  const systemRevision = pinned.stdout.trim();
  if (systemRevision === '') { stderrLine(`firn rebuild: git returned an empty revision for ${systemRoot}`); return { tag: 'failed', status: 65 }; }
  const clean = executeEffect(effects[1], tracePath, traceId, revision);
  if (clean.tag === 'failed') return clean;
  if (clean.stdout.trim() === '') return { tag: 'pinned', target: r.makeSystemTarget(snapshot, systemRoot, systemRevision) };
  stderrLine(`firn rebuild: system flake ${systemRoot} has uncommitted tracked changes; commit or discard them first`);
  return { tag: 'failed', status: 65 };
}
function preparePinned(target: r.Target, host: string, platform: r.Platform, snapshotDirectory: string, tracePath: string | null, traceId: string): number {
  const result = executeEffects(r.preparationEffects(target, host, platform, snapshotDirectory), tracePath, traceId, targetRevision(target));
  if (result.tag === 'failed') return failPhase(result.status);
  const builtPath = result.stdout.trim();
  if (r.exactStorePath(builtPath)) { globalThis.firn_host_out(`firn prepare: prepared ${targetRevision(target)} ${builtPath}\n`); return 0; }
  stderrLine('firn prepare: build did not return one exact Nix store path');
  return 65;
}
function runPinned(target: r.Target, host: string, platform: r.Platform, snapshotDirectory: string, tracePath: string | null, traceId: string): number {
  const result = executeEffects(r.preparationEffects(target, host, platform, snapshotDirectory), tracePath, traceId, targetRevision(target));
  if (result.tag === 'failed') return failPhase(result.status);
  const builtPath = result.stdout.trim();
  if (r.exactStorePath(builtPath)) return activate(target, host, platform, builtPath, tracePath, traceId);
  stderrLine('firn rebuild: build did not return one exact Nix store path');
  return 65;
}
function prepare(root: string, systemRoot: string | null, host: string, snapshotDirectory: string, tracePath: string | null, traceId: string): number {
  const pinned = pinSnapshot(root, tracePath, traceId);
  if (pinned.tag === 'failed') return failPhase(pinned.status);
  const selected = selectPlatform(pinned.snapshot.revision, tracePath, traceId);
  if (selected.tag === 'rejected') { stderrLine(`firn prepare: unsupported platform '${selected.name}'`); return 69; }
  const target = pinTarget(pinned.snapshot, systemRoot, tracePath, traceId);
  return target.tag === 'failed' ? failPhase(target.status) : preparePinned(target.target, host, selected.platform, snapshotDirectory, tracePath, traceId);
}
function rebuild(root: string, systemRoot: string | null, host: string, snapshotDirectory: string, tracePath: string | null, traceId: string): number {
  const pinned = pinSnapshot(root, tracePath, traceId);
  if (pinned.tag === 'failed') return failPhase(pinned.status);
  const selected = selectPlatform(pinned.snapshot.revision, tracePath, traceId);
  if (selected.tag === 'rejected') { stderrLine(`firn rebuild: unsupported platform '${selected.name}'`); return 69; }
  const target = pinTarget(pinned.snapshot, systemRoot, tracePath, traceId);
  return target.tag === 'failed' ? failPhase(target.status) : runPinned(target.target, host, selected.platform, snapshotDirectory, tracePath, traceId);
}
function rollbackError(message: string, status: number): number { stderrLine(`firn rollback: ${message}`); return status; }
const rollbackStopped = (generation: string, status: number): number => rollbackError(`stopped at first failure (status ${status}) while selecting generation ${generation}; verify the active generation before retrying`, status);
function activateGeneration(generation: string, builtPath: string, tracePath: string | null, traceId: string): number {
  const result = executeEffects(r.rollbackActivationEffects(generation, builtPath), tracePath, traceId, `generation-${generation}`);
  if (result.tag === 'failed') return rollbackStopped(generation, result.status);
  globalThis.firn_host_out(`firn rollback: activated generation ${generation} (${builtPath})\n`);
  return 0;
}
function validateGenerationClosure(generation: string, builtPath: string, tracePath: string | null, traceId: string): number {
  const result = executeEffect(r.generationClosureCheckEffect(builtPath), tracePath, traceId, `generation-${generation}`);
  return result.tag === 'failed' ? rollbackError(`generation ${generation} does not contain an executable switch-to-configuration (status ${result.status}); no rollback was attempted`, result.status) : activateGeneration(generation, builtPath, tracePath, traceId);
}
function resolveGeneration(generation: string, tracePath: string | null, traceId: string): number {
  const result = executeEffect(r.generationResolveEffect(generation), tracePath, traceId, `generation-${generation}`);
  if (result.tag === 'failed') return rollbackError(`generation ${generation} could not be resolved to an existing system profile (status ${result.status}); no rollback was attempted`, result.status);
  const builtPath = result.stdout.trim();
  return r.exactStorePath(result.stdout) ? validateGenerationClosure(generation, builtPath, tracePath, traceId) : rollbackError(`generation ${generation} resolved to an invalid Nix store path; no rollback was attempted`, 65);
}
function validateGenerationListing(generation: string, listing: string, tracePath: string | null, traceId: string): number {
  const current = r.currentGeneration(listing);
  if (current === null) return rollbackError('the active generation was not reported; no rollback was attempted', 65);
  if (!r.generationPresent(listing, generation)) return rollbackError(`generation ${generation} is not present in the system profile; no rollback was attempted`, 65);
  if (!r.generationLess(generation, current)) return rollbackError(`generation ${generation} is not older than active generation ${current}; no rollback was attempted`, 65);
  return resolveGeneration(generation, tracePath, traceId);
}
function runRollbackLinux(generation: string, tracePath: string | null, traceId: string): number {
  const result = executeEffect(r.generationQueryEffect(r.linuxPlatform()), tracePath, traceId, `generation-${generation}`);
  return result.tag === 'failed' ? rollbackStopped(generation, result.status) : validateGenerationListing(generation, result.stdout, tracePath, traceId);
}
function runRollback(generation: string, tracePath: string | null, traceId: string): number {
  if (!r.generationToken(generation)) return rollbackError('target must be an exact positive decimal generation (for example, 1200)', 64);
  const result = executeEffect(r.platformEffect(), tracePath, traceId, `generation-${generation}`);
  if (result.tag === 'failed') return rollbackStopped(generation, result.status);
  const selected = r.platformFromName(result.stdout.trim());
  if (selected.tag === 'rejected') return rollbackError(`unsupported platform '${selected.name}'`, 69);
  return r.linux(selected.platform) ? runRollbackLinux(generation, tracePath, traceId) : rollbackError('explicit-generation rollback is supported only on NixOS', 69);
}
const requiredEnv = (name: string): string | null => { const value = globalThis.firn_host_env(name); return value !== null && value.length > 0 ? value : null; };
function repositoryRoot(): string | null { const explicit = requiredEnv('FIRN_REPO'), home = requiredEnv('HOME'); return explicit ?? (home === null ? null : `${home}/code/nixos-config/main`); }
function systemFlakeRoot(): string | null {
  const explicit = requiredEnv('FIRN_SYSTEM_FLAKE'), home = requiredEnv('HOME');
  const root = explicit ?? (home === null ? null : `${home}/code/south/main`);
  return root !== null && globalThis.firn_host_git_checkout(root) ? root : null;
}
function snapshotDirectory(): string { return requiredEnv('FIRN_SNAPSHOT_DIR') ?? `${requiredEnv('XDG_RUNTIME_DIR') ?? '/tmp'}/firn-rebuild-snapshot-${globalThis.firn_host_pid()}`; }
function usageError(): number {
  stderrLine('Usage:\n  firn host prepare <host>\n  firn host activate <exact-store-path>\n  firn host rebuild <host>\n  firn host rollback <generation>');
  return 64;
}
export function runCommand(args: string[]): number {
  if (args.length !== 3 || args[0] !== 'host') return usageError();
  const tracePath = requiredEnv('FIRN_TRACE_PATH'), traceId = requiredEnv('FIRN_TRACE_ID') ?? '';
  if (args[1] === 'activate') return activateExactPath(args[2], tracePath, traceId);
  if (args[1] === 'rollback') return runRollback(args[2], tracePath, traceId);
  if (args[1] === 'prepare' || args[1] === 'rebuild') {
    const root = repositoryRoot(), snapshotPath = snapshotDirectory();
    if (root === null) { stderrLine(`firn ${args[1]}: FIRN_REPO and HOME are not set`); return 64; }
    return (args[1] === 'prepare' ? prepare : rebuild)(root, systemFlakeRoot(), args[2], snapshotPath, tracePath, traceId);
  }
  return usageError();
}
