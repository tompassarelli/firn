#!/usr/bin/env bun

import {
  appendFileSync,
  mkdirSync,
  readFileSync,
} from 'node:fs';
import { dirname } from 'node:path';

const errnoByCode = Object.freeze({
  E2BIG: 7,
  EACCES: 13,
  EFBIG: 27,
  EIO: 5,
  EISDIR: 21,
  ENOENT: 2,
  ENOSPC: 28,
  ENOTDIR: 20,
  EPERM: 1,
});
const errno = error => errnoByCode[error?.code] ?? 5;
const failed = error => Object.freeze({ tag: 'error', errno: errno(error) });

globalThis.bridge_env = name => process.env[name] ?? null;
globalThis.bridge_result_tag = result => String(result.tag);
globalThis.bridge_result_int = (result, field) => Number(result[field]);
globalThis.bridge_result_string = (result, field) => String(result[field]);
globalThis.bridge_err = text => { process.stderr.write(text); return null; };
globalThis.bridge_out = text => { process.stdout.write(text); return null; };
globalThis.bridge_wall_nanoseconds = () => Date.now() * 1_000_000;

globalThis.bridge_format_iso8601 = nanoseconds => {
  try {
    return Object.freeze({
      tag: 'ok',
      text: new Date(Math.trunc(nanoseconds / 1_000_000)).toISOString(),
    });
  } catch (error) { return failed(error); }
};

globalThis.bridge_read_text_bounded = (path, limit) => {
  try {
    const bytes = readFileSync(path);
    if (bytes.byteLength > limit) return failed({ code: 'EFBIG' });
    return Object.freeze({ tag: 'ok', text: bytes.toString('utf8') });
  } catch (error) { return failed(error); }
};

globalThis.bridge_make_parent_directories = path => {
  try { mkdirSync(dirname(path), { recursive: true }); return 0; }
  catch (error) { return errno(error); }
};

globalThis.bridge_append_text = (path, text) => {
  try { appendFileSync(path, text, { encoding: 'utf8', mode: 0o600 }); return 0; }
  catch (error) { return errno(error); }
};

globalThis.bridge_run_capture = (argv, input, limit) => {
  try {
    const child = Bun.spawnSync({
      cmd: argv,
      env: process.env,
      stdin: Buffer.from(input),
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const stdout = child.stdout.toString();
    const stderr = child.stderr.toString();
    if (Buffer.byteLength(stdout) + Buffer.byteLength(stderr) > limit) {
      return failed({ code: 'E2BIG' });
    }
    return Object.freeze({
      tag: 'ok',
      status: child.exitCode ?? 1,
      stdout,
      stderr,
    });
  } catch (error) { return failed(error); }
};

globalThis.bridge_run_inherit = argv => {
  try {
    const child = Bun.spawnSync({
      cmd: argv,
      env: process.env,
      stdin: 'inherit',
      stdout: 'inherit',
      stderr: 'inherit',
    });
    return child.exitCode ?? 1;
  } catch (error) { return -errno(error); }
};

const modulePath = process.env.FIRN_WINDOW_MARKS_MODULE
  ?? new URL('../lib/firn/window-marks-native.js', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(Bun.argv.slice(2));
