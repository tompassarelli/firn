import * as policy from './system_policy.ts';

function rawBash(seed: number, command: string): policy.RawHookEvent {
  return { toolName: 'Bash', command, filePath: null, sessionId: `session${seed === 0 ? '' : seed}`,
    payloadOversized: false, guardsOff: false, introUnseen: false };
}
function caseEventDecodingAndRefusal(seed: number): boolean {
  const event = policy.decodeHookEvent(rawBash(seed, 'nixos-rebuild switch'));
  const refusal = policy.decideHook(rawBash(seed, 'sudo nixos-rebuild test'));
  const echo = policy.decideHook(rawBash(seed, 'echo nixos-rebuild switch'));
  const upgrade = policy.decideHook(rawBash(seed, 'firn repo upgrade now'));
  return event.tag === 'HookBash' && event.command === 'nixos-rebuild switch'
    && refusal.tag === 'HookRefuse' && echo.tag === 'HookPass' && echo.token
    && upgrade.tag === 'HookPass' && upgrade.token;
}
function caseEditIntroductionAndExits(seed: number): boolean {
  const event: policy.RawHookEvent = { toolName: 'Edit', command: null,
    filePath: `/code/nixos-config/file${seed === 0 ? '' : seed}.nix`,
    sessionId: `session${seed === 0 ? '' : seed}`, payloadOversized: false,
    guardsOff: false, introUnseen: true };
  const decision = policy.decideHook(event);
  return decision.tag === 'HookInject' && decision.context === policy.firnDigest
    && policy.hookExitCode(policy.decideHook(event)) === 0;
}
function pinArgumentsProperty(seed: number): boolean {
  const accepted = policy.parsePinArguments([`--warn-days=${seed % 61}`]);
  const rejected = policy.parsePinArguments(['--warn-days', `no${seed}`]);
  return accepted.tag === 'PinArgumentsAccepted' && accepted.warnDays === seed % 61
    && rejected.tag === 'PinArgumentsRejected';
}
function casePinArgumentsAndAssertions(seed: number): boolean {
  return pinArgumentsProperty(seed)
    && policy.validSri('sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=')
    && !policy.validSri('sha256-not-a-checksum');
}
function casePinExitDecision(seed: number): boolean {
  const arguments_ = policy.parsePinArguments([]);
  const evidence: policy.PinEvidence[] = [{ kind: `fixed-output${seed === 0 ? '' : seed}`,
    location: 'module.nix:4', value: 'https://example.test/source',
    verificationUrl: 'https://example.test/source', reachable: true, checksum: 'sha256-invalid' }];
  const inputs: policy.LockInput[] = [{ name: 'nixpkgs', revision: `abcdef${seed === 0 ? '' : seed}`, modified: 0 }];
  const report = policy.pinPolicy(arguments_, 2678400, evidence, inputs);
  return report.exitCode === 1 && report.diagnostics[0].code === 'malformed-checksum'
    && report.diagnostics[1].code === 'stale-lock-input';
}
export function runScenarios(): number {
  if (caseEventDecodingAndRefusal(0) && caseEditIntroductionAndExits(0)
    && casePinArgumentsAndAssertions(0) && casePinExitDecision(0)) return 0;
  console.log('FAIL system_policy scenarios');
  return 1;
}
export function runProperties(samples: number): number {
  if (samples <= 0) return 1;
  let seed = 73421;
  for (let index = 0; index < samples; index++) {
    if (!pinArgumentsProperty(seed)) {
      console.log(`FAIL pin argument conservation seed=${seed}`);
      return 1;
    }
    seed = seed * 48271 % 2147483647;
  }
  return 0;
}
