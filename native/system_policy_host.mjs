#!/usr/bin/env bun

import {
  lstatSync,
  readFileSync,
  realpathSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';

const errnoByCode = Object.freeze({ EACCES: 13, EEXIST: 17, EFBIG: 27,
  EIO: 5, EISDIR: 21, ENOENT: 2, ENOTDIR: 20, EPERM: 1 });
const errno = error => errnoByCode[error?.code] ?? 5;
const ok = fields => Object.freeze({ tag: 'ok', ...fields });
const failure = error => Object.freeze({ tag: 'error', errno: errno(error) });

globalThis.host_getenv = (bridge, name) => bridge.getenv(name);
globalThis.host_read_text_bounded = (bridge, path, limit) => bridge.readTextBounded(path, limit);
globalThis.host_path_kind = (bridge, path) => bridge.pathKind(path);
globalThis.host_write_text_atomic = (bridge, path, text) => bridge.writeTextAtomic(path, text);
globalThis.host_real_path = (bridge, path) => bridge.realPath(path);
globalThis.host_read_stdin_bounded = (bridge, limit) => bridge.readStdinBounded(limit);
globalThis.host_out = (bridge, text) => bridge.out(text);
globalThis.host_result_tag = result => String(result.tag);
globalThis.host_result_int = (result, field) => Number(result[field]);
globalThis.host_result_string = (result, field) => String(result[field]);

const stdinBytes = await Bun.stdin.bytes();

const bridge = Object.freeze({
  getenv(name) { return process.env[name] ?? null; },
  out(text) { process.stdout.write(text); },
  readTextBounded(path, limit) {
    try {
      const bytes = readFileSync(path);
      return bytes.byteLength > limit ? failure({ code: 'EFBIG' }) : ok({ text: bytes.toString('utf8') });
    } catch (error) { return failure(error); }
  },
  pathKind(path) {
    try { lstatSync(path); return ok({}); }
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
  realPath(path) {
    try { return ok({ path: realpathSync(path) }); }
    catch (error) { return failure(error); }
  },
  readStdinBounded(limit) {
    return stdinBytes.byteLength > limit
      ? failure({ code: 'EFBIG' })
      : ok({ text: new TextDecoder().decode(stdinBytes) });
  },
});

const modulePath = process.env.FIRN_SYSTEM_POLICY_MODULE
  ?? new URL('../lib/firn/system-policy-native.js', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(bridge);
