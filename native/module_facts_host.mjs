// SPDX-License-Identifier: MIT OR Apache-2.0

import { closeSync, existsSync, openSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';

const questions = {
  tags: 'all ?m, ?t where ?m is tagged ?t',
  optIn: 'all ?m, ?t where ?m can opt into ?t',
  overrides: 'all ?m, ?t, ?p, ?v where ?t sets ?p to ?v for ?m',
  hosts: 'all ?h where ?h is a Host',
  platform: 'all ?h, ?p where ?h runs ?p',
  enables: 'all ?h, ?t where ?h enables ?t',
  adds: 'all ?h, ?m, ?t where ?h adds ?m to ?t',
  drops: 'all ?h, ?m, ?t where ?h drops ?m from ?t',
  disables: 'all ?h, ?m where ?h disables ?m',
  active: 'all ?h, ?m where ?m is tag-enabled on ?h',
  turnsOn: 'all ?h, ?m where ?h turns on ?m',
  turnsOff: 'all ?h, ?m where ?h turns off ?m',
};

function galileo() {
  const runtime = process.env.FIRN_RUNTIME_BIN;
  return runtime && existsSync(join(runtime, 'galileo')) ? join(runtime, 'galileo') : 'galileo';
}

function query(root, question, paths = []) {
  const run = Bun.spawnSync([galileo(), 'query', ...paths, question, '--json'], {
    cwd: root, stdout: 'pipe', stderr: 'pipe', timeout: 120000,
  });
  if (run.exitCode !== 0) {
    throw new Error(run.stderr.toString().trim() || `galileo query exited ${run.exitCode}`);
  }
  return JSON.parse(run.stdout.toString());
}

function entry(modules, name) {
  if (!modules.has(name)) modules.set(name, { tags: [], optIn: [], overrides: new Map() });
  return modules.get(name);
}

export function readModuleFacts(root) {
  try {
    const modules = new Map();
    for (const row of query(root, questions.tags)) entry(modules, row.m).tags.push(row.t);
    for (const row of query(root, questions.optIn)) entry(modules, row.m).optIn.push(row.t);
    for (const row of query(root, questions.overrides)) {
      const overrides = entry(modules, row.m).overrides;
      if (!overrides.has(row.t)) overrides.set(row.t, new Map());
      overrides.get(row.t).set(row.p, row.v);
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
    for (const name of query(root, questions.hosts)) hostEntry(hosts, name);
    for (const row of query(root, questions.platform)) hostEntry(hosts, row.h).platform = row.p;
    for (const row of query(root, questions.enables)) hostEntry(hosts, row.h).enables.push(row.t);
    for (const row of query(root, questions.adds)) push(hostEntry(hosts, row.h).adds, row.t, row.m);
    for (const row of query(root, questions.drops)) push(hostEntry(hosts, row.h).drops, row.t, row.m);
    for (const row of query(root, questions.disables)) hostEntry(hosts, row.h).disables.push(row.m);
    for (const row of query(root, questions.active)) hostEntry(hosts, row.h).active.push(row.m);
    for (const row of query(root, questions.turnsOn)) hostEntry(hosts, row.h).turnsOn.push(row.m);
    for (const row of query(root, questions.turnsOff)) hostEntry(hosts, row.h).turnsOff.push(row.m);
    return Object.freeze({ status: 0, value: hosts, message: '' });
  } catch (error) {
    return Object.freeze({ status: 1, value: null, message: String(error?.message ?? error) });
  }
}

export function buildGenerated(root) {
  const run = Bun.spawnSync([galileo(), 'build'], {
    cwd: root, stdout: 'inherit', stderr: 'inherit', timeout: 120000,
  });
  return run.exitCode ?? 1;
}

const noHost = Object.freeze({ platform: 'linux', enables: [], adds: new Map(),
  drops: new Map(), disables: [], active: [], turnsOn: [], turnsOff: [] });
const hostFacts = (hosts, name) => hosts.get(name) ?? noHost;

const flakeProgram = ['flake.gal', 'modules', 'config'];

export function readFlakeInputs(root) {
  try {
    const rows = query(root, 'all ?m, ?n, ?u where ?m needs flake input ?n from ?u', flakeProgram);
    return Object.freeze({ status: 0, value: rows.map((row) => [row.m, row.n, row.u]), message: '' });
  } catch (error) {
    return Object.freeze({ status: 1, value: null, message: String(error?.message ?? error) });
  }
}

export function runFlakeBuild(root) {
  const run = Bun.spawnSync([galileo(), 'build', ...flakeProgram], {
    cwd: root, stdout: 'inherit', stderr: 'inherit', timeout: 300000,
  });
  return run.exitCode ?? 1;
}

function factAnchor(lines, fact) {
  const [host, verb, ...rest] = fact.split(' ');
  const last = (test) => lines.findLastIndex((line) => test(line.trim().split(/\s+/)));
  const ofHost = (words) => words[0] === host;
  const tagLine = (words) => ofHost(words) && ['enables', 'adds', 'drops'].includes(words[1]);
  let index = -1;
  if (verb === 'adds' || verb === 'drops') {
    const tag = rest.at(-1);
    index = last((w) => ofHost(w) && ((w[1] === 'enables' && w[2] === tag)
      || ((w[1] === 'adds' || w[1] === 'drops') && w.at(-1) === tag)));
  } else if (verb === 'disables') {
    index = last((w) => ofHost(w) && w[1] === 'disables');
  }
  if (index < 0 && verb !== 'disables') index = last(tagLine);
  if (index < 0) index = last(ofHost);
  return index < 0 ? lines.length : index + 1;
}

export function editFactLines(source, remove, add) {
  const trailing = source.endsWith('\n');
  const lines = source.length === 0 ? [] : (trailing ? source.slice(0, -1) : source).split('\n');
  for (const fact of remove) {
    const index = lines.findIndex((line) => line.trim() === fact);
    if (index < 0) return { status: 1, value: null, message: `fact '${fact}' is not stated in this file` };
    lines.splice(index, 1);
  }
  for (const fact of add) lines.splice(factAnchor(lines, fact), 0, fact);
  return { status: 0, value: lines.length === 0 ? '' : `${lines.join('\n')}\n`, message: '' };
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
