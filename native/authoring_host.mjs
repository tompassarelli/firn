#!/usr/bin/env bun

import {
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { dirname } from 'node:path';

const ok = fields => Object.freeze({ tag: 'ok', ...fields });
const failure = error => Object.freeze({ tag: 'error', errno: errnoOf(error) });
const errnoOf = error => {
  const value = Number(error?.errno);
  if (Number.isInteger(value) && value !== 0) return Math.abs(value);
  const known = { E2BIG: 7, EACCES: 13, EEXIST: 17, EFBIG: 27, EINVAL: 22,
    EIO: 5, EISDIR: 21, ENOENT: 2, ENOTDIR: 20, EPERM: 1 };
  return known[error?.code] ?? 5;
};

globalThis.host_getenv = (bridge, name) => bridge.getenv(name);
globalThis.host_path_kind = (bridge, path) => bridge.pathKind(path);
globalThis.host_read_text_bounded = (bridge, path, limit) =>
  bridge.readTextBounded(path, limit);
globalThis.host_make_parent_directories = (bridge, path) =>
  bridge.makeParentDirectories(path);
globalThis.host_write_text_atomic = (bridge, path, text) =>
  bridge.writeTextAtomic(path, text);
globalThis.host_list_directory_bounded = (bridge, path, limit) =>
  bridge.listDirectoryBounded(path, limit);
globalThis.host_run_inherit = (bridge, argv) => bridge.runInherit(argv);
globalThis.host_out = (bridge, text) => bridge.out(text);
globalThis.host_err = (bridge, text) => bridge.err(text);
globalThis.host_result_tag = result => String(result.tag);
globalThis.host_result_int = (result, field) => Number(result[field]);
globalThis.host_result_string = (result, field) => String(result[field]);
globalThis.host_result_strings = (result, field) => result[field];

const bridge = Object.freeze({
  getenv(name) { return process.env[name] ?? null; },
  out(text) { process.stdout.write(text); },
  err(text) { process.stderr.write(text); },
  pathKind(path) {
    try {
      const stat = lstatSync(path);
      const kind = stat.isFile() ? 1 : stat.isDirectory() ? 2 : stat.isSymbolicLink() ? 3 : 4;
      return ok({ kind });
    } catch (error) { return failure(error); }
  },
  readTextBounded(path, limit) {
    try {
      if (statSync(path).size > limit) return failure({ code: 'EFBIG' });
      return ok({ text: readFileSync(path, 'utf8') });
    } catch (error) { return failure(error); }
  },
  makeParentDirectories(path) {
    try { mkdirSync(dirname(path), { recursive: true }); return ok({}); }
    catch (error) { return failure(error); }
  },
  writeTextAtomic(path, text) {
    const temporary = `${path}.firn-${process.pid}-${crypto.randomUUID()}`;
    try {
      writeFileSync(temporary, text, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
      renameSync(temporary, path);
      return ok({});
    } catch (error) {
      try { unlinkSync(temporary); } catch {}
      return failure(error);
    }
  },
  listDirectoryBounded(path, limit) {
    try {
      const entries = readdirSync(path, { encoding: 'utf8' });
      return entries.length > limit ? failure({ code: 'E2BIG' }) : ok({ entries });
    } catch (error) { return failure(error); }
  },
  runInherit(argv) {
    try {
      const child = Bun.spawnSync({
        cmd: argv,
        env: process.env,
        stdin: 'inherit',
        stdout: 'inherit',
        stderr: 'inherit',
      });
      return child.exitCode ?? 1;
    } catch (error) { return -errnoOf(error); }
  },
});

const modulePath = process.env.FIRN_AUTHORING_MODULE
  ?? new URL('../lib/firn-authoring-native.js', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(bridge, Bun.argv.slice(2));
