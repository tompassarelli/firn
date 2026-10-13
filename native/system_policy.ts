export type Diagnostic = { level: string; code: string; message: string };
export type PolicyReport = { diagnostics: Diagnostic[]; exitCode: number };
export type RawHookEvent = {
  toolName: string; command: string | null; filePath: string | null;
  sessionId: string; payloadOversized: boolean; guardsOff: boolean; introUnseen: boolean;
};
export type HookEvent = { tag: 'HookBash'; command: string }
  | { tag: 'HookEdit'; path: string } | { tag: 'HookIgnored'; toolName: string };
export type HookDecision = { tag: 'HookPass'; token: boolean }
  | { tag: 'HookInject'; context: string } | { tag: 'HookRefuse'; reason: string };
export type PinArguments = { tag: 'PinArgumentsAccepted'; warnDays: number }
  | { tag: 'PinArgumentsHelp'; token: boolean }
  | { tag: 'PinArgumentsRejected'; message: string };
export type PinEvidence = {
  kind: string; location: string; value: string; verificationUrl: string;
  reachable: boolean; checksum: string | null;
};
export type LockInput = { name: string; revision: string; modified: number | null };
export type ChecksumAssertion = { path: string; expected: string; actual: string };
export type LicenseEvidence = { checksums: ChecksumAssertion[]; readmeLicense: string | null };

export const firnDigest = 'You are editing the Firn system configuration. Edit .gal sources, never '
  + '.nix; run firn repo build and firn repo validate after .gal changes. '
  + 'Check uncertain Galileo syntax and schema facts with the runtime\'s '
  + 'galileo help, galileo refs and galileo schema explain. '
  + 'Keep Tom-maintained and high-churn project source and build outputs out '
  + 'of the boot/system closure. A derivation, package, worktree, or filesystem '
  + 'pin does not grant closure admission; use a dev shell, user runtime, or '
  + 'direct out-of-store launcher unless an exact stable machine/service '
  + 'responsibility is declared. '
  + 'Use firn\'s committed-snapshot workflow for system changes; raw '
  + 'nixos-rebuild, darwin-rebuild, and nh switching are forbidden. '
  + 'Secrets use sops-nix only.';
export const blockedCommandReason = 'BLOCKED: raw nixos-rebuild/darwin-rebuild/nh bypasses the sanctioned '
  + 'snapshot workflow. Use `firn rebuild` after the relevant checks pass '
  + 'and owned changes are committed.';
export const expectedReadmeLicense = '## License\n\n'
  + 'Firn is dual-licensed under either the [MIT License](LICENSE-MIT) or the\n'
  + '[Apache License, Version 2.0](LICENSE-APACHE), at your option\n'
  + '(`MIT OR Apache-2.0`).';

function startsAt(text: string, offset: number, token: string): boolean {
  return offset >= 0 && offset + token.length <= text.length
    && text.slice(offset, offset + token.length) === token;
}
function whitespace(character: string): boolean {
  return character === ' ' || character === '\t' || character === '\n';
}
function separator(character: string): boolean {
  return whitespace(character) || ';&|(`)'.includes(character);
}
function skipWhitespace(text: string, offset: number): number {
  while (offset < text.length && whitespace(text.slice(offset, offset + 1))) offset++;
  return offset;
}
function tokenEnd(text: string, offset: number): number {
  while (offset < text.length && !separator(text.slice(offset, offset + 1))) offset++;
  return offset;
}
function wordAt(text: string, offset: number, word: string): boolean {
  const after = offset + word.length;
  return startsAt(text, offset, word) && (after === text.length || separator(text.slice(after, after + 1)));
}
function nextWord(text: string, offset: number): number {
  return skipWhitespace(text, tokenEnd(text, skipWhitespace(text, offset)));
}
function stripPrivilegePrefix(text: string, offset: number): number {
  const start = skipWhitespace(text, offset);
  return wordAt(text, start, 'sudo') || wordAt(text, start, 'doas') ? nextWord(text, start) : start;
}
function commandAnchor(text: string, offset: number): boolean {
  return offset === 0 || '\n;&|(`'.includes(text.slice(offset - 1, offset));
}
function nthWordAt(text: string, offset: number, word: string): boolean {
  return wordAt(text, nextWord(text, offset), word);
}
function commandHasWord(text: string, commandOffset: number, wanted: string): boolean {
  for (let cursor = nextWord(text, commandOffset); cursor < text.length && !commandAnchor(text, cursor); cursor = nextWord(text, cursor)) {
    if (wordAt(text, cursor, wanted)) return true;
    if (tokenEnd(text, cursor) === cursor) return false;
  }
  return false;
}
function refusalAt(command: string, offset: number): boolean {
  if (!commandAnchor(command, offset)) return false;
  const start = stripPrivilegePrefix(command, offset);
  return (wordAt(command, start, 'nixos-rebuild')
    && ['switch', 'boot', 'test'].some(word => commandHasWord(command, start, word)))
    || (wordAt(command, start, 'darwin-rebuild')
      && ['switch', 'boot'].some(word => commandHasWord(command, start, word)))
    || (wordAt(command, start, 'nh') && (nthWordAt(command, start, 'switch')
      || nthWordAt(command, start, 'boot') || (nthWordAt(command, start, 'os')
        && (nthWordAt(command, nextWord(command, start), 'switch')
          || nthWordAt(command, nextWord(command, start), 'boot')))));
}
function refusedCommand(command: string): boolean {
  for (let offset = 0; offset < command.length; offset++) if (refusalAt(command, offset)) return true;
  return false;
}
export function decodeHookEvent(raw: RawHookEvent): HookEvent {
  if (raw.toolName === 'Bash' && raw.command !== null) return { tag: 'HookBash', command: raw.command };
  if (['Edit', 'Write', 'MultiEdit'].includes(raw.toolName) && raw.filePath !== null) return { tag: 'HookEdit', path: raw.filePath };
  return { tag: 'HookIgnored', toolName: raw.toolName };
}
export function firnPath(path: string): boolean {
  return path.includes('/code/nixos-config/');
}
export function decideHook(raw: RawHookEvent): HookDecision {
  if (raw.guardsOff || raw.payloadOversized) return { tag: 'HookPass', token: true };
  const event = decodeHookEvent(raw);
  if (event.tag === 'HookBash' && refusedCommand(event.command)) return { tag: 'HookRefuse', reason: blockedCommandReason };
  if (event.tag === 'HookEdit' && raw.introUnseen && firnPath(event.path)) return { tag: 'HookInject', context: firnDigest };
  return { tag: 'HookPass', token: true };
}
export function hookExitCode(_decision: HookDecision): number { return 0; }
function decimalValue(text: string): number | null {
  if (text.length === 0) return null;
  let value = 0;
  for (const character of text) {
    const digit = '0123456789'.indexOf(character);
    if (digit < 0) return null;
    value = value * 10 + digit;
  }
  return value;
}
export function parsePinArguments(args: string[]): PinArguments {
  let warnDays = 30;
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === '-h' || arg === '--help') return { tag: 'PinArgumentsHelp', token: true };
    let value: number | null;
    if (arg === '--warn-days') {
      if (index + 1 >= args.length) return { tag: 'PinArgumentsRejected', message: 'error: --warn-days requires a value' };
      value = decimalValue(args[++index]);
    } else if (startsAt(arg, 0, '--warn-days=')) value = decimalValue(arg.slice(12));
    else return { tag: 'PinArgumentsRejected', message: `error: unknown argument: ${arg}` };
    if (value === null) return { tag: 'PinArgumentsRejected', message: 'error: --warn-days must be a non-negative integer' };
    warnDays = value;
  }
  return { tag: 'PinArgumentsAccepted', warnDays };
}
export function validSri(checksum: string): boolean {
  return checksum.length === 51 && checksum.startsWith('sha256-') && checksum.slice(50, 51) === '='
    && [...checksum.slice(7, 50)].every(character => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'.includes(character));
}
function validSha256(checksum: string): boolean {
  return checksum.length === 64 && [...checksum].every(character => '0123456789abcdef'.includes(character));
}
function handPinDiagnostic(evidence: PinEvidence): Diagnostic | null {
  if (evidence.checksum !== null && !validSri(evidence.checksum)) return {
    level: 'error', code: 'malformed-checksum',
    message: `ERROR hand-pin ${evidence.kind} ${evidence.location} ${evidence.value} (${evidence.checksum})`,
  };
  if (!evidence.reachable) return {
    level: 'error', code: 'unverified-pin', message: `ERROR hand-pin ${evidence.kind} ${evidence.location} ${evidence.value}`,
  };
  return null;
}
function lockInputDiagnostic(now: number, warnDays: number, input: LockInput): Diagnostic | null {
  if (input.modified === null) return { level: 'error', code: 'unverifiable-lock-input', message: `ERROR flake-input ${input.name} rev ${input.revision} age unverifiable` };
  const ageDays = Math.trunc(Math.max(0, now - input.modified) / 86400);
  return ageDays > warnDays ? { level: 'error', code: 'stale-lock-input', message: `STALE flake-input ${input.name} rev ${input.revision} age ${ageDays}d` } : null;
}
export function pinPolicy(arguments_: PinArguments, now: number, evidence: PinEvidence[], inputs: LockInput[]): PolicyReport {
  if (arguments_.tag === 'PinArgumentsHelp') return { diagnostics: [], exitCode: 0 };
  if (arguments_.tag === 'PinArgumentsRejected') return { diagnostics: [{ level: 'error', code: 'invalid-arguments', message: arguments_.message }], exitCode: 2 };
  const diagnostics = [
    ...evidence.map(handPinDiagnostic),
    ...inputs.map(input => lockInputDiagnostic(now, arguments_.warnDays, input)),
  ].filter((diagnostic): diagnostic is Diagnostic => diagnostic !== null);
  return { diagnostics, exitCode: diagnostics.some(diagnostic => diagnostic.level === 'error') ? 1 : 0 };
}
export function licensePolicy(evidence: LicenseEvidence): PolicyReport {
  const diagnostics: Diagnostic[] = evidence.checksums.filter(assertion => !validSha256(assertion.actual) || assertion.expected !== assertion.actual)
    .map(assertion => ({ level: 'error', code: 'license-checksum', message: `${assertion.path} differs from the canonical repository copy (expected ${assertion.expected}, got ${assertion.actual})` }));
  if (evidence.readmeLicense === null) diagnostics.push({ level: 'error', code: 'license-section', message: 'README.md has no License section' });
  else if (evidence.readmeLicense !== expectedReadmeLicense) diagnostics.push({ level: 'error', code: 'license-notice', message: 'README.md License section does not match the canonical dual-license notice' });
  return diagnostics.some(diagnostic => diagnostic.level === 'error') ? { diagnostics, exitCode: 1 }
    : { diagnostics: [{ level: 'ok', code: 'license-ok', message: 'ok: Firn license files and README declare MIT OR Apache-2.0 consistently' }], exitCode: 0 };
}
