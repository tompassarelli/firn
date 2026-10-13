export interface DryRunResult { exitStatus: number; output: string }
export interface ImpactInput { host: string; dryRun: DryRunResult; currentSystemDerivations: string[] }
export interface ExpensiveBuild { name: string; estimate: string }
export interface RebuildImpact { builds: string[]; fetches: string[]; notableBuilds: ExpensiveBuild[]; newPackages: string[] }
export type ImpactResult = { tag: 'ready'; impact: RebuildImpact; text: string } | { tag: 'failed'; text: string };
export const splitLines = (text: string): string[] => text === '' ? [] : text.endsWith('\n') ? text.slice(0, -1).split('\n') : text.split('\n');
function storeName(path: string): string {
  const base = path.slice(path.lastIndexOf('/') + 1).replace(/\.drv$/, '');
  return base.slice(base.indexOf('-') + 1);
}
function plannedImpact(output: string): RebuildImpact {
  let section = '';
  const builds: string[] = [], fetches: string[] = [];
  for (const line of splitLines(output)) {
    if (line.includes(' derivations will be built') || line.includes('will be built:')) section = 'build';
    else if (line.includes(' paths will be fetched') || line.includes('will be fetched')) section = 'fetch';
    else if (line === '') section = '';
    else if (line.trim().startsWith('/nix/store/')) {
      if (section === 'build') builds.push(line.trim());
      else if (section === 'fetch') fetches.push(line.trim());
    }
  }
  return { builds, fetches, notableBuilds: [], newPackages: [] };
}
function expensiveEstimate(name: string): string | null {
  if (name.includes('firefox') || name.includes('librewolf')) return '~30-45 min';
  if (name.includes('chromium')) return '~60 min';
  if (name.startsWith('linux-')) return '~15-20 min';
  if (name.startsWith('ghc-')) return '~30 min';
  if (['llvm-', 'clang-', 'rustc-', 'rust-'].some(prefix => name.startsWith(prefix))) return '~20 min';
  if (name.startsWith('nodejs-')) return '~5 min';
  if (name.startsWith('qt6-')) return '~15 min';
  return name.includes('webkit') ? '~30 min' : null;
}
function enrichImpact(impact: RebuildImpact, currentSystemDerivations: string[]): RebuildImpact {
  const notableBuilds: ExpensiveBuild[] = [];
  for (const path of impact.builds) {
    const name = storeName(path), estimate = expensiveEstimate(name);
    if (estimate !== null) notableBuilds.push({ name, estimate });
  }
  const newPackages = impact.fetches.map(storeName).filter(name => /^[a-z]/.test(name) && !['source', 'patch', 'hook', 'setup', 'wrapper', 'env', 'builder'].some(word => name.includes(word)) && !currentSystemDerivations.some(path => path.includes(name)));
  return { ...impact, notableBuilds, newPackages };
}
function renderImpact(host: string, impact: RebuildImpact): string {
  const { builds, fetches, notableBuilds, newPackages } = impact;
  if (builds.length === 0 && fetches.length === 0) return `Rebuild impact (${host}):\n  System is up to date — nothing to build or fetch.\n`;
  let text = `Rebuild impact (${host}):\n`;
  if (builds.length > 0) text += `  * ${builds.length} derivation(s) to build\n`;
  if (fetches.length > 0) text += `  * ${fetches.length} path(s) to fetch from cache\n`;
  text += '\n';
  if (notableBuilds.length > 0) text += `  Notable rebuilds:\n${notableBuilds.map(build => `    ${build.name} (${build.estimate}, local build)\n`).join('')}\n`;
  if (newPackages.length > 0 && newPackages.length <= 10) text += `  New packages:\n${newPackages.map(name => `    ${name} (binary cache hit)\n`).join('')}\n`;
  text += notableBuilds.length > 0 ? '  Estimated: has expensive local builds — expect significant wait time\n' : builds.length > 10 ? '  Estimated: many small builds, ~5-15 min wall time\n' : builds.length > 0 ? '  Estimated: minor builds + cache hits, ~2-5 min wall time\n' : '  Estimated: all cache hits, ~1-2 min wall time\n';
  return text;
}
export function interpret(input: ImpactInput): ImpactResult {
  if (input.dryRun.exitStatus !== 0) return { tag: 'failed', text: `firn impact: dry-run failed (eval error?)\n${splitLines(input.dryRun.output).slice(-5).map(line => `${line}\n`).join('')}` };
  const impact = enrichImpact(plannedImpact(input.dryRun.output), input.currentSystemDerivations);
  return { tag: 'ready', impact, text: renderImpact(input.host, impact) };
}
