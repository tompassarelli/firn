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
import type { AuthoringBridge } from './authoring_native.ts';

const ok = (fields: Record<string, unknown>) => Object.freeze({ tag: 'ok' as const, ...fields });
const failure = (error: unknown) => Object.freeze({ tag: 'error' as const, errno: errnoOf(error) });
const errnoOf = (error: any) => {
  const value = Number(error?.errno);
  if (Number.isInteger(value) && value !== 0) return Math.abs(value);
  const known = { E2BIG: 7, EACCES: 13, EEXIST: 17, EFBIG: 27, EINVAL: 22,
    EIO: 5, EISDIR: 21, ENOENT: 2, ENOTDIR: 20, EPERM: 1 };
  return known[error?.code] ?? 5;
};

const bridge: AuthoringBridge = Object.freeze({
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
  runNix(root, files) {
    try {
      const child = Bun.spawnSync({
        cmd: ['nix-instantiate', '--parse', ...files],
        cwd: root,
        env: process.env,
        stdin: 'ignore',
        stdout: 'pipe',
        stderr: 'pipe',
      });
      const status = child.exitCode ?? 1;
      if (status !== 0) {
        process.stdout.write(child.stdout);
        process.stderr.write(child.stderr);
      }
      return status;
    } catch (error) { return -errnoOf(error); }
  },
});

const modulePath = process.env.FIRN_AUTHORING_MODULE
  ?? new URL('./authoring_native.ts', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(bridge, Bun.argv.slice(2));
