#!/usr/bin/env bun

import { hostname } from 'node:os';
import { lstatSync, readFileSync } from 'node:fs';

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

const host = {
  env: name => process.env[name] ?? null,
  err: text => { process.stderr.write(text); },
  out: text => { process.stdout.write(text); },
  wallNanoseconds: () => Date.now() * 1_000_000,
  stdoutTty: () => Boolean(process.stdout.isTTY),
};

host.hostname = () => {
  try { return Object.freeze({ tag: 'ok', hostname: hostname() }); }
  catch (error) { return failed(error); }
};

host.pathKind = path => {
  try {
    const stat = lstatSync(path);
    return Object.freeze({
      tag: 'ok',
      kind: stat.isFile() ? 1 : stat.isDirectory() ? 2 : stat.isSymbolicLink() ? 3 : 4,
    });
  } catch (error) { return failed(error); }
};

host.readTextBounded = (path, limit) => {
  try {
    const bytes = readFileSync(path);
    if (bytes.byteLength > limit) return failed({ code: 'EFBIG' });
    return Object.freeze({ tag: 'ok', text: bytes.toString('utf8') });
  } catch (error) { return failed(error); }
};

host.runCapture = (argv, input, limit) => {
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
  ?? new URL('./firn_views_native.ts', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(Bun.argv.slice(2), host);
