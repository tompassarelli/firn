// SPDX-License-Identifier: MIT OR Apache-2.0

import { closeSync, existsSync, openSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';

const readJson = path => JSON.parse(readFileSync(path, 'utf8'));
function names(root, directory) {
  const path = join(root, directory);
  return existsSync(path) ? readdirSync(path, { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name).sort() : [];
}

function entry(modules, name) {
  if (!modules.has(name)) modules.set(name, { tags: [], optIn: [], overrides: new Map() });
  return modules.get(name);
}

export function readModuleFacts(root) {
  try {
    const modules = new Map();
    for (const name of names(root, 'modules')) {
      const path = join(root, 'modules', name, 'metadata.json');
      const data = existsSync(path) ? readJson(path) : {};
      const item = entry(modules, name);
      item.tags = data.tags ?? [];
      item.optIn = data.optIn ?? [];
      item.overrides = new Map(Object.entries(data.overrides ?? {}).map(([tag, values]) => [tag, new Map(Object.entries(values).map(([path, value]) => [path, JSON.stringify(value)]))]));
    }
    return Object.freeze({ status: 0, value: modules, message: '' });
  } catch (error) {
    return Object.freeze({ status: 1, value: null, message: String(error?.message ?? error) });
  }
}

function hostEntry(hosts, name) {
  if (!hosts.has(name)) {
    hosts.set(name, { platform: 'linux', enables: [], adds: new Map(), drops: new Map(),
      disables: [], active: [], turnsOn: [], turnsOff: [] });
  }
  return hosts.get(name);
}

function push(map, key, value) {
  if (!map.has(key)) map.set(key, []);
  map.get(key).push(value);
}

export function readHostFacts(root) {
  try {
    const hosts = new Map();
    const modules = readModuleFacts(root);
    if (modules.status !== 0) throw new Error(modules.message);
    for (const name of names(root, 'hosts')) {
      const path = join(root, 'hosts', name, 'tags.json');
      if (!existsSync(path)) continue;
      const data = readJson(path), item = hostEntry(hosts, name);
      Object.assign(item, data);
      item.adds = new Map(Object.entries(data.adds ?? {}));
      item.drops = new Map(Object.entries(data.drops ?? {}));
      const allowed = item.platform === 'darwin' ? readJson(join(root, 'config/darwin-modules.json')) : null;
      item.active = [...modules.value].filter(([module, facts]) => !item.disables.includes(module) && !item.turnsOff.includes(module)
        && (!allowed || allowed.includes(module))
        && item.enables.some(tag => !item.drops.get(tag)?.includes(module)
          && (facts.tags.includes(tag) || item.adds.get(tag)?.includes(module))))
        .map(([module]) => module).sort();
    }
    return Object.freeze({ status: 0, value: hosts, message: '' });
  } catch (error) {
    return Object.freeze({ status: 1, value: null, message: String(error?.message ?? error) });
  }
}

export function buildGenerated(root) {
  const run = Bun.spawnSync(['nix', 'eval', '--raw', `path:${root}#nixosConfigurations`, '--apply', 'hosts: builtins.concatStringsSep "\\n" (map (name: hosts.${name}.config.system.build.toplevel.drvPath) (builtins.attrNames hosts))'], {
    cwd: root, stdout: 'ignore', stderr: 'inherit',
  });
  return run.exitCode ?? 1;
}

const noHost = Object.freeze({ platform: 'linux', enables: [], adds: new Map(),
  drops: new Map(), disables: [], active: [], turnsOn: [], turnsOff: [] });
const hostFacts = (hosts, name) => hosts.get(name) ?? noHost;

export function readFlakeInputs(root) {
  try {
    const rows = names(root, 'modules').flatMap(module => {
      const path = join(root, 'modules', module, 'metadata.json');
      return existsSync(path) ? Object.entries(readJson(path).flakeInputs ?? {}).map(([name, url]) => [module, name, url]) : [];
    });
    return Object.freeze({ status: 0, value: rows, message: '' });
  } catch (error) {
    return Object.freeze({ status: 1, value: null, message: String(error?.message ?? error) });
  }
}

export function runFlakeBuild(root) {
  const facts = readFlakeInputs(root);
  if (facts.status !== 0) { process.stderr.write(facts.message + '\n'); return 1; }
  const declared = new Map();
  for (const [module, name, url] of facts.value) {
    if (declared.has(name) && declared.get(name) !== url) {
      process.stderr.write(`firn flake-input resolve: conflicting URLs for '${name}' from ${module}\n`);
      return 1;
    }
    declared.set(name, url);
  }
  const path = join(root, 'flake.nix');
  let source = readFileSync(path, 'utf8');
  for (const [name, url] of declared) {
    if (!/^[a-zA-Z][a-zA-Z0-9_-]*$/.test(name)) throw new Error(`invalid flake input name '${name}'`);
    const existing = new RegExp(`(\\b${name}\\s*=\\s*\\{[^{}]*?\\burl\\s*=\\s*)"[^"\\n]*"`);
    const dotted = new RegExp(`(\\b${name}\\.url\\s*=\\s*)"[^"\\n]*"`);
    if (existing.test(source)) source = source.replace(existing, (_, prefix) => prefix + JSON.stringify(url));
    else if (dotted.test(source)) source = source.replace(dotted, (_, prefix) => prefix + JSON.stringify(url));
    else {
      if (!/\binputs\s*=\s*\{/.test(source)) throw new Error('flake.nix needs a literal inputs attrset');
      source = source.replace(/(\binputs\s*=\s*\{)/, `$1\n    ${name}.url = ${JSON.stringify(url)};`);
    }
  }
  const previous = readFileSync(path, 'utf8');
  if (source !== previous) writeFileSync(path, source);
  return 0;
}

export function editFactLines(source, remove, add) {
  const data = JSON.parse(source);
  function change(fact, adding) {
    const [host, verb, module, , tag] = fact.split(' ');
    const field = { enables: 'enables', disables: 'disables', adds: 'adds', drops: 'drops' }[verb];
    if (!field) throw new Error(`unsupported host fact '${fact}'`);
    const values = verb === 'adds' || verb === 'drops'
      ? (data[field] ??= {})[tag] ??= [] : data[field] ??= [];
    const index = values.indexOf(module);
    if (!adding && index < 0) throw new Error(`fact '${fact}' is not stated in this file`);
    if (adding && index < 0) values.push(module);
    if (!adding) values.splice(index, 1);
    if ((verb === 'adds' || verb === 'drops') && values.length === 0) delete data[field][tag];
  }
  try {
    for (const fact of remove) change(fact, false);
    for (const fact of add) change(fact, true);
    return { status: 0, value: JSON.stringify(data, null, 2) + '\n', message: '' };
  } catch (error) { return { status: 1, value: null, message: String(error?.message ?? error) }; }
}

let temporaryId = 0;

export function editHostFacts(path, remove, add) {
  let source;
  try {
    source = readFileSync(path, 'utf8');
  } catch (error) {
    return Object.freeze({ status: 1, value: null, message: String(error?.message ?? error) });
  }
  const edited = editFactLines(source, remove, add);
  if (edited.status !== 0) return Object.freeze(edited);
  const temporary = join(dirname(path), `.${basename(path)}.firn-${process.pid}-${temporaryId++}`);
  let descriptor = null;
  try {
    descriptor = openSync(temporary, 'wx', 0o644);
    writeFileSync(descriptor, edited.value, 'utf8');
    closeSync(descriptor);
    descriptor = null;
    renameSync(temporary, path);
    return Object.freeze({ status: 0, value: null, message: '' });
  } catch (error) {
    if (descriptor !== null) {
      try { closeSync(descriptor); } catch {}
    }
    try { unlinkSync(temporary); } catch {}
    return Object.freeze({ status: 1, value: null, message: String(error?.message ?? error) });
  }
}

const empty = Object.freeze({ tags: [], optIn: [], overrides: new Map() });
const facts = (modules, name) => modules.get(name) ?? empty;

export const moduleFactsBridge = Object.freeze({
  readModuleFacts,
  readFlakeInputs,
  runFlakeBuild,
  factTags(modules, name) { return [...facts(modules, name).tags].sort(); },
  factOptIn(modules, name) { return [...facts(modules, name).optIn].sort(); },
  factOverrideTags(modules, name) { return [...facts(modules, name).overrides.keys()].sort(); },
  factOverridePaths(modules, name, tag) {
    return [...(facts(modules, name).overrides.get(tag)?.keys() ?? [])].sort();
  },
  factOverrideLiteral(modules, name, tag, path) {
    return facts(modules, name).overrides.get(tag).get(path);
  },
  moduleFactsMessage(result) { return result.message; },
  readHostFacts,
  buildGenerated,
  editHostFacts,
  hostDeclared(hosts, name) { return hosts.has(name); },
  hostPlatform(hosts, name) { return hostFacts(hosts, name).platform; },
  hostEnabledTags(hosts, name) { return [...hostFacts(hosts, name).enables].sort(); },
  hostAdds(hosts, name, tag) { return [...(hostFacts(hosts, name).adds.get(tag) ?? [])].sort(); },
  hostDrops(hosts, name, tag) { return [...(hostFacts(hosts, name).drops.get(tag) ?? [])].sort(); },
  hostDisabled(hosts, name) { return [...hostFacts(hosts, name).disables].sort(); },
  hostActive(hosts, name) { return [...hostFacts(hosts, name).active].sort(); },
  hostTurnsOn(hosts, name) { return [...hostFacts(hosts, name).turnsOn].sort(); },
  hostTurnsOff(hosts, name) { return [...hostFacts(hosts, name).turnsOff].sort(); },
});
