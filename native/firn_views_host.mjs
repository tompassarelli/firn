#!/usr/bin/env bun

import { hostname } from 'node:os';
import { lstatSync, readFileSync, readdirSync } from 'node:fs';

const errnoByCode = Object.freeze({
  E2BIG: 7,
  EACCES: 13,
  EFBIG: 27,
  EIO: 5,
  EISDIR: 21,
  ENOENT: 2,
  ENOTDIR: 20,
  EPERM: 1,
});

const errno = error => errnoByCode[error?.code] ?? 5;
const failed = error => Object.freeze({ tag: 'error', errno: errno(error) });

globalThis.bridge_env = name => process.env[name] ?? null;
globalThis.bridge_result_tag = result => String(result.tag);
globalThis.bridge_result_int = (result, field) => Number(result[field]);
globalThis.bridge_result_string = (result, field) => String(result[field]);
globalThis.bridge_result_strings = (result, field) => result[field];
globalThis.bridge_err = text => { process.stderr.write(text); return null; };
globalThis.bridge_wall_nanoseconds = () => Date.now() * 1_000_000;
globalThis.bridge_stdout_tty = () => Boolean(process.stdout.isTTY);

globalThis.bridge_hostname = () => {
  try { return Object.freeze({ tag: 'ok', hostname: hostname() }); }
  catch (error) { return failed(error); }
};

globalThis.bridge_path_kind = path => {
  try {
    const stat = lstatSync(path);
    return Object.freeze({
      tag: 'ok',
      kind: stat.isFile() ? 1 : stat.isDirectory() ? 2 : stat.isSymbolicLink() ? 3 : 4,
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

globalThis.bridge_list_directory_bounded = (path, limit) => {
  try {
    const entries = readdirSync(path, { encoding: 'utf8' });
    return entries.length > limit
      ? failed({ code: 'E2BIG' })
      : Object.freeze({ tag: 'ok', entries });
  } catch (error) { return failed(error); }
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

const modulePath = process.env.FIRN_VIEWS_MODULE
  ?? new URL('../lib/firn/views-native.js', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(Bun.argv.slice(2));
