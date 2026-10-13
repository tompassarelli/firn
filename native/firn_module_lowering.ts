import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

const moduleItem = /^(?:arguments:|let |option |enable:|"enable":|imports:|config(?:\s|$)|for )/;

function declaresEnable(module: string, source: string): boolean {
  const path = `(?:myConfig\\.modules\\.${module}|"myConfig"\\."modules"\\."${module}")`;
  const indent = /^nix module$/m.test(source) ? '  ' : '';
  if (new RegExp(`^${indent}(?:enable|"enable"):`, 'm').test(source)
    || new RegExp(`^${indent}option ${path}\\.(?:enable|"enable"):`, 'm').test(source)) return true;
  let group = false;
  for (const line of source.split('\n')) {
    if (new RegExp(`^${indent}option ${path}$`).test(line)) {
      group = true;
    } else if (group) {
      if (line.trim() && !line.startsWith(`${indent}  `)) group = false;
      if (group && new RegExp(`^${indent}  enable:`).test(line)) return true;
    }
  }
  return false;
}

export function lowerModuleSource(name: string, source: string, declaredElsewhere = false): string {
  const match = /^modules\/([a-z0-9-]+)\/([^/]+)$/.exec(name.replace(/\.gal$/, ''));
  if (!match) return source;
  const [, module, file] = match;
  const lines = source.split('\n');
  const explicit = lines.findIndex(line => /^nix (?:module|file)$/.test(line));
  const implicit = explicit < 0 ? lines.findIndex(line => moduleItem.test(line)) : -1;
  const boundary = explicit >= 0 ? explicit : implicit >= 0 ? implicit : lines.length;
  const facts = lines.slice(0, boundary).flatMap(line => {
    const tags = /^tags:\s*(.*)$/.exec(line);
    if (!tags) return [line];
    const names = tags[1].split(',').map(tag => tag.trim());
    if (names.some(tag => !/^[a-z0-9-]+$/.test(tag))) {
      throw new Error(`${name}: tags need comma-separated tag names`);
    }
    return names.map(tag => `${module} is tagged ${tag}`);
  });
  if (file === 'default' && !facts.includes(`${module} is a Module`)) {
    const afterUses = facts.findLastIndex(line => line.startsWith('use ')) + 1;
    facts.splice(afterUses, 0, `${module} is a Module`);
    if (!facts.includes('use firn/tags')) facts.unshift('use firn/tags');
  }
  if (explicit >= 0 && lines[explicit] === 'nix file') {
    return [...facts, ...lines.slice(explicit)].join('\n');
  }
  const body = explicit >= 0
    ? lines.slice(explicit + 1)
    : lines.slice(boundary).map(line => line ? `  ${line}` : line);
  if (!body.some(line => /^  arguments:/.test(line))) {
    body.unshift('  arguments: config, lib, pkgs, ...');
  }
  let hasEnable = declaredElsewhere || declaresEnable(module, source);
  const lowered = body.map(line => {
    const enable = /^  (enable|"enable"):\s*(.+)$/.exec(line);
    if (enable) {
      hasEnable = true;
      const path = enable[1] === '"enable"'
        ? `"myConfig"."modules"."${module}"."enable"`
        : `myConfig.modules.${module}.enable`;
      return `  option ${path}: enable ${enable[2]}`;
    }
    if (new RegExp(`^  option (?:myConfig\\.modules\\.${module}\\.enable|"myConfig"\\."modules"\\."${module}"\\."enable"): `).test(line)) {
      hasEnable = true;
    }
    return implicit >= 0 && line === '  config'
      ? `  config when config.myConfig.modules.${module}.enable`
      : line;
  });
  if (file === 'default' && explicit < 0 && !hasEnable) {
    const ending = lowered.at(-1) === '' ? lowered.length - 1 : lowered.length;
    lowered.splice(ending, 0, `  option myConfig.modules.${module}.enable: enable "${module}"`);
  }
  return [...facts, 'nix module', ...lowered].join('\n');
}

if (import.meta.main) {
  const input = await Bun.stdin.text();
  const records = input.split('\0');
  if (records.at(-1) !== '' || records.length % 2 !== 1) {
    throw new Error('firn module lowering needs name/source pairs');
  }
  const output: string[] = [];
  let root = process.cwd();
  while (!existsSync(join(root, '.git')) && dirname(root) !== root
    && !(existsSync(join(root, 'config/galileo-revision')) && existsSync(join(root, 'flake.gal')))) root = dirname(root);
  const firn = existsSync(join(root, 'config/galileo-revision')) && existsSync(join(root, 'flake.gal'));
  const declared = new Set<string>();
  for (let index = 0; index < records.length - 1; index += 2) {
    const match = /^modules\/([a-z0-9-]+)\//.exec(records[index]);
    if (!match) continue;
    const module = match[1];
    const source = records[index + 1];
    if (declaresEnable(module, source)) {
      declared.add(module);
    }
  }
  for (let index = 0; index < records.length - 1; index += 2) {
    const module = /^modules\/([a-z0-9-]+)\//.exec(records[index])?.[1];
    output.push(firn
      ? lowerModuleSource(records[index], records[index + 1], module !== undefined && declared.has(module))
      : records[index + 1]);
  }
  process.stdout.write(`${output.join('\0')}\0`);
}
