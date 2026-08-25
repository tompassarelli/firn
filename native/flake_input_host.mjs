// SPDX-License-Identifier: MIT OR Apache-2.0

import { chmodSync, lstatSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';

const modulePath = process.env.FIRN_FLAKE_INPUT_MODULE
  ?? new URL('../lib/firn-flake-input.js', import.meta.url).pathname;
const { run } = await import(modulePath);

function errno(error) {
  return Math.abs(Number(error?.errno ?? 1));
}

function result(status, value = null) {
  return Object.freeze({ status, value });
}

const bridge = Object.freeze({
  env(name) { return process.env[name] ?? null; },
  out(text) { process.stdout.write(text); },
  err(text) { process.stderr.write(text); },
  status(value) { return value.status; },
  value(value) { return value.value; },
  listDirectory(path, maximum) {
    try {
      const names = readdirSync(path);
      return names.length > maximum ? result(27) : result(0, names);
    } catch (error) {
      return result(errno(error));
    }
  },
  pathKind(path) {
    try {
      const stat = lstatSync(path);
      return result(0, stat.isDirectory() ? 2 : stat.isSymbolicLink() ? 3 : 1);
    } catch (error) {
      return result(errno(error));
    }
  },
  readText(path, maximum) {
    try {
      const bytes = readFileSync(path);
      return bytes.length > maximum ? result(27) : result(0, bytes.toString('utf8'));
    } catch (error) {
      return result(errno(error));
    }
  },
  writeTextAtomic(path, text) {
    const temporary = `${path}.firn-${process.pid}-${crypto.randomUUID()}.tmp`;
    try {
      writeFileSync(temporary, text, { flag: 'wx', mode: 0o600 });
      chmodSync(temporary, 0o644);
      renameSync(temporary, path);
      return 0;
    } catch (error) {
      try { unlinkSync(temporary); } catch {}
      return errno(error);
    }
  },
});

process.exitCode = run(bridge, Bun.argv.slice(2));
