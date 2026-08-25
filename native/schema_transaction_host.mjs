// SPDX-License-Identifier: MIT OR Apache-2.0

import { spawnSync } from 'node:child_process';
import {
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';

const errnoByCode = Object.freeze({
  E2BIG: 7,
  EACCES: 13,
  EEXIST: 17,
  EFBIG: 27,
  EINVAL: 22,
  EIO: 5,
  EISDIR: 21,
  EMFILE: 24,
  ENOENT: 2,
  ENOMEM: 12,
  ENOSPC: 28,
  ENOTDIR: 20,
  EPERM: 1,
});

function errno(error) {
  return errnoByCode[error?.code] ?? 5;
}

function exactNanoseconds(value) {
  const billion = 1_000_000_000n;
  return {
    seconds: (value / billion).toString(),
    nanoseconds: (value % billion).toString(),
  };
}

globalThis.bridge_result_tag = result => result.tag;
globalThis.bridge_result_int = (result, field) => result[field];
globalThis.bridge_result_string = (result, field) => result[field];
globalThis.bridge_result_strings = (result, field) => result[field];
globalThis.bridge_env = name => process.env[name] ?? null;
globalThis.bridge_out = text => { process.stdout.write(text); return null; };
globalThis.bridge_err = text => { process.stderr.write(text); return null; };

globalThis.bridge_read_text_bounded = (absolute, limit) => {
  try {
    const bytes = readFileSync(absolute);
    if (bytes.byteLength > limit) return { tag: 'error', errno: 27 };
    return { tag: 'ok', text: bytes.toString('utf8') };
  } catch (error) {
    return { tag: 'error', errno: errno(error) };
  }
};

globalThis.bridge_list_directory_bounded = (absolute, limit) => {
  try {
    const entries = readdirSync(absolute, { encoding: 'utf8' });
    if (entries.length > limit) return { tag: 'error', errno: 7 };
    return { tag: 'ok', entries };
  } catch (error) {
    return { tag: 'error', errno: errno(error) };
  }
};

globalThis.bridge_path_kind = absolute => {
  try {
    const stat = lstatSync(absolute, { bigint: true });
    const modified = exactNanoseconds(stat.mtimeNs);
    return {
      tag: 'ok',
      kind: stat.isFile() ? 1 : stat.isDirectory() ? 2 : stat.isSymbolicLink() ? 3 : 0,
      mtimeSeconds: modified.seconds,
      mtimeNanoseconds: modified.nanoseconds,
    };
  } catch (error) {
    return { tag: 'error', errno: errno(error) };
  }
};

globalThis.bridge_make_parent_directories = absolute => {
  try {
    mkdirSync(dirname(absolute), { recursive: true });
    return 0;
  } catch (error) {
    return errno(error);
  }
};

globalThis.bridge_write_text_atomic = (absolute, contents) => {
  const temporary = `${absolute}.tmp.${process.pid}.${randomUUID()}`;
  try {
    writeFileSync(temporary, contents, { encoding: 'utf8', flag: 'wx' });
    renameSync(temporary, absolute);
    return 0;
  } catch (error) {
    try { unlinkSync(temporary); } catch {}
    return errno(error);
  }
};

globalThis.bridge_run_capture = (argv, input, limit) => {
  const result = spawnSync(argv[0], argv.slice(1), {
    encoding: 'utf8',
    env: process.env,
    input,
    maxBuffer: limit,
  });
  if (result.error) return { tag: 'error', errno: errno(result.error) };
  return {
    tag: 'ok',
    status: result.status ?? 1,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
};

const modulePath = process.env.FIRN_SCHEMA_MODULE
  ?? new URL('../lib/firn/schema-transaction-native.js', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(Bun.argv.slice(2));
