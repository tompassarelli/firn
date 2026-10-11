// SPDX-License-Identifier: MIT OR Apache-2.0

import { existsSync } from 'node:fs';
import { join } from 'node:path';

const questions = {
  tags: 'all ?m, ?t where ?m is tagged ?t',
  optIn: 'all ?m, ?t where ?m can opt into ?t',
  overrides: 'all ?m, ?t, ?p, ?v where ?t sets ?p to ?v for ?m',
};

function galileo() {
  const runtime = process.env.FIRN_RUNTIME_BIN;
  return runtime && existsSync(join(runtime, 'galileo')) ? join(runtime, 'galileo') : 'galileo';
}

function query(root, question) {
  const run = Bun.spawnSync([galileo(), 'query', question, '--json'], {
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

const empty = Object.freeze({ tags: [], optIn: [], overrides: new Map() });
const facts = (modules, name) => modules.get(name) ?? empty;

export const moduleFactsBridge = Object.freeze({
  readModuleFacts,
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
});
