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

type Part = { text: string; start: number; end: number; implied: boolean };
type MappedLine = { text: string; parts: Part[] };

export function lowerModuleSourceMapped(name: string, source: string, declaredElsewhere = false) {
  let offset = 0;
  const lines: MappedLine[] = source.split('\n').map(text => {
    const line = { text, parts: [{ text, start: offset, end: offset + text.length, implied: false }] };
    offset += text.length + 1;
    return line;
  });
  const copied = (text: string, start: number): Part => ({ text, start, end: start + text.length, implied: false });
  const generated = (text: string, anchor: Part): Part => ({ text, start: anchor.start, end: anchor.end, implied: true });
  const lineOf = (...parts: Part[]): MappedLine => ({ text: parts.map(part => part.text).join(''), parts });
  const match = /^modules\/([a-z0-9-]+)\/([^/]+)$/.exec(name.replace(/\.gal$/, ''));
  let output = lines;
  if (match) {
    const [, module, file] = match;
    const explicit = lines.findIndex(line => /^nix (?:module|file)$/.test(line.text));
    const implicit = explicit < 0 ? lines.findIndex(line => moduleItem.test(line.text)) : -1;
    const boundary = explicit >= 0 ? explicit : implicit >= 0 ? implicit : lines.length;
    const anchorLine = lines[Math.min(boundary, lines.length - 1)];
    const anchor = anchorLine.parts[0];
    const synthetic = (text: string) => lineOf(generated(text, anchor));
    const facts = lines.slice(0, boundary).flatMap(line => {
      const tags = /^tags:\s*(.*)$/.exec(line.text);
      if (!tags) return [line];
      const names = tags[1].split(',').map(tag => tag.trim());
      if (names.some(tag => !/^[a-z0-9-]+$/.test(tag))) {
        throw new Error(`${name}: tags need comma-separated tag names`);
      }
      let from = line.text.indexOf(':') + 1;
      return names.map(tag => {
        const at = line.text.indexOf(tag, from);
        from = at + tag.length;
        const origin = copied(tag, line.parts[0].start + at);
        return lineOf(generated(`${module} is tagged `, origin), origin);
      });
    });
    if (file === 'default' && !facts.some(line => line.text === `${module} is a Module`)) {
      const afterUses = facts.findLastIndex(line => line.text.startsWith('use ')) + 1;
      facts.splice(afterUses, 0, synthetic(`${module} is a Module`));
      if (!facts.some(line => line.text === 'use firn/tags')) facts.unshift(synthetic('use firn/tags'));
    }
    if (explicit >= 0 && lines[explicit].text === 'nix file') {
      output = [...facts, ...lines.slice(explicit)];
    } else {
      const body = explicit >= 0
        ? lines.slice(explicit + 1)
        : lines.slice(boundary).map(line => line.text ? lineOf(generated('  ', line.parts[0]), ...line.parts) : line);
      if (!body.some(line => /^  arguments:/.test(line.text))) {
        body.unshift(synthetic('  arguments: config, lib, pkgs, ...'));
      }
      let hasEnable = declaredElsewhere || declaresEnable(module, source);
      const lowered = body.map(line => {
        const enable = /^  (enable|"enable"):\s*(.+)$/.exec(line.text);
        if (enable) {
          hasEnable = true;
          const path = enable[1] === '"enable"'
            ? `"myConfig"."modules"."${module}"."enable"`
            : `myConfig.modules.${module}.enable`;
          const raw = line.parts.at(-1)!;
          const suffix = enable[2];
          const suffixStart = raw.start + raw.text.length - suffix.length;
          const field = copied(enable[1], raw.start + raw.text.indexOf(enable[1]));
          return lineOf(generated(`  option ${path}: enable `, field), copied(suffix, suffixStart));
        }
        if (new RegExp(`^  option (?:myConfig\\.modules\\.${module}\\.enable|"myConfig"\\."modules"\\."${module}"\\."enable"): `).test(line.text)) {
          hasEnable = true;
        }
        if (implicit >= 0 && line.text === '  config') {
          return lineOf(...line.parts, generated(` when config.myConfig.modules.${module}.enable`, line.parts.at(-1)!));
        }
        return line;
      });
      if (file === 'default' && explicit < 0 && !hasEnable) {
        const ending = lowered.at(-1)?.text === '' ? lowered.length - 1 : lowered.length;
        lowered.splice(ending, 0, synthetic(`  option myConfig.modules.${module}.enable: enable "${module}"`));
      }
      output = [...facts, explicit >= 0 ? lines[explicit] : synthetic('nix module'), ...lowered];
    }
  }
  const map: number[][] = [];
  let bytes = 0;
  const parts = output.flatMap((line, index) => index === output.length - 1
    ? line.parts
    : [...line.parts, generated('\n', line.parts.at(-1)!)]);
  for (const part of parts) {
    const end = bytes + Buffer.byteLength(part.text);
    if (end > bytes) map.push([bytes, end, Buffer.byteLength(source.slice(0, part.start)), Buffer.byteLength(source.slice(0, part.end)), Number(part.implied)]);
    bytes = end;
  }
  return { text: output.map(line => line.text).join('\n'), map };
}

export function lowerModuleSource(name: string, source: string, declaredElsewhere = false): string {
  return lowerModuleSourceMapped(name, source, declaredElsewhere).text;
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
    const lowered = lowerModuleSourceMapped(firn ? records[index] : '', records[index + 1], module !== undefined && declared.has(module));
    output.push(lowered.text, lowered.map.map(span => span.join(',')).join('\n'));
  }
  process.stdout.write(`${output.join('\0')}\0`);
}
