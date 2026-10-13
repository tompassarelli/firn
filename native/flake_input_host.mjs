// SPDX-License-Identifier: MIT OR Apache-2.0

import { readFileSync } from 'node:fs';
import { moduleFactsBridge } from './module_facts_host.mjs';

const modulePath = process.env.FIRN_FLAKE_INPUT_MODULE
  ?? new URL('./flake_input_family.ts', import.meta.url).pathname;
const { run } = await import(modulePath);

function errno(error) {
  return Math.abs(Number(error?.errno ?? 1));
}

function result(status, value = null) {
  return Object.freeze({ status, value });
}

const bridge = Object.freeze({
  ...moduleFactsBridge,
  env(name) { return process.env[name] ?? null; },
  out(text) { process.stdout.write(text); },
  err(text) { process.stderr.write(text); },
  status(value) { return value.status; },
  value(value) { return value.value; },
  readText(path, maximum) {
    try {
      const bytes = readFileSync(path);
      return bytes.length > maximum ? result(27) : result(0, bytes.toString('utf8'));
    } catch (error) {
      return result(errno(error));
    }
  },
});

process.exitCode = run(bridge, Bun.argv.slice(2));
