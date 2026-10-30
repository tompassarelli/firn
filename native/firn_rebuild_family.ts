import { interpret, splitLines } from './impact.ts';
import { runCommand } from './rebuild_native.ts';
const maxImpactOutput = 16777216;
function repositoryRoot(): string | null {
  const explicit = globalThis.firn_host_env('FIRN_REPO');
  if (explicit !== null) return explicit;
  const home = globalThis.firn_host_env('HOME');
  return home === null ? null : `${home}/code/nixos-config/main`;
}
function currentHost(): string {
  const configured = globalThis.firn_host_env('FIRN_HOST');
  if (configured !== null) return configured;
  const result = globalThis.firn_host_capture(['hostname'], 4096);
  if (result[0] === 'error') return 'whiterabbit';
  const hostname = result[2].trim();
  return result[1] === 0 && hostname.length > 0 ? hostname : 'whiterabbit';
}
function currentSystemDerivations(): string[] {
  const result = globalThis.firn_host_capture(['nix', 'path-info', '/run/current-system', '--derivation'], maxImpactOutput);
  return result[0] === 'ok' && result[1] === 0 ? splitLines(result[2]) : [];
}
function runImpact(host: string): number {
  const root = repositoryRoot();
  if (root === null) { globalThis.firn_host_err('firn impact: FIRN_REPO and HOME are not set\n'); return 1; }
  const attribute = `${root}#nixosConfigurations.${host}.config.system.build.toplevel`;
  const result = globalThis.firn_host_capture(['nix', 'build', attribute, '--dry-run'], maxImpactOutput);
  if (result[0] === 'error') { globalThis.firn_host_err(`firn impact: cannot run nix: errno ${result[1]}\n`); return 1; }
  const assessment = interpret({ host, dryRun: { exitStatus: result[1], output: result[2] + result[3] }, currentSystemDerivations: currentSystemDerivations() });
  if (assessment.tag === 'failed') { globalThis.firn_host_err(assessment.text); return 1; }
  globalThis.firn_host_out(assessment.text);
  return 0;
}
function usageError(): number {
  globalThis.firn_host_err('Usage:\n  firn host impact [<host>]\n  firn host prepare [<host>]\n  firn host activate <exact-store-path>\n  firn host rebuild [<host>]\n  firn host rollback <generation>\n');
  return 64;
}
export function foreignRebuild(args: string[]): string | null {
  if (args[0] !== 'host' || args[1] !== 'rebuild' || args.length !== 3 || args[2] === currentHost()) return null;
  return `firn rebuild: ${args[2]} is not this machine (${currentHost()}); run: firn host deploy ${args[2]}\n`;
}
export function run(args: string[]): number {
  if ((args.length !== 2 && args.length !== 3) || args[0] !== 'host') return usageError();
  const refusal = foreignRebuild(args);
  if (refusal !== null) { globalThis.firn_host_err(refusal); return 64; }
  const edge = args[1], leaf = args.length === 3 ? args[2] : currentHost();
  if (edge === 'impact') return runImpact(leaf);
  if (edge === 'prepare' || edge === 'rebuild') return runCommand(['host', edge, leaf]);
  if (edge === 'activate' || edge === 'rollback') return args.length === 3 ? runCommand(['host', edge, leaf]) : usageError();
  return usageError();
}
