// SPDX-License-Identifier: MIT OR Apache-2.0

import {
  closeSync,
  constants,
  fsyncSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  readSync,
  renameSync,
  rmSync,
  unlinkSync,
  writeFileSync,
  writeSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const decoder = new TextDecoder();
const descriptors = new Map();
const locks = new Map();
let nextDescriptor = 100_000;

function errnoOf(error) {
  return Math.abs(Number(error?.errno ?? 5));
}

function sleep(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

function alive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 1) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function atomicWrite(path, text) {
  const temporary = `${path}.tmp.${process.pid}.${crypto.randomUUID()}`;
  let descriptor = -1;
  try {
    descriptor = openSync(temporary,
      constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
    writeFileSync(descriptor, text, 'utf8');
    fsyncSync(descriptor);
    closeSync(descriptor);
    descriptor = -1;
    renameSync(temporary, path);
    const directory = openSync(dirname(path), constants.O_RDONLY);
    try { fsyncSync(directory); } finally { closeSync(directory); }
    return ['ok'];
  } catch (error) {
    if (descriptor >= 0) closeSync(descriptor);
    try { unlinkSync(temporary); } catch {}
    return ['error', errnoOf(error)];
  }
}

function readTextBounded(path, limit) {
  try {
    const bytes = readFileSync(path);
    return bytes.byteLength <= limit
      ? ['ok', decoder.decode(bytes)]
      : ['error', 27];
  } catch (error) {
    return ['error', errnoOf(error)];
  }
}

function lockExclusive(path) {
  const child = spawn('flock', [
    '--exclusive', '--nonblock', '--conflict-exit-code', '73', path,
    'sh', '-c', 'printf locked; cat >/dev/null',
  ], { stdin: 'pipe', stdout: 'pipe', stderr: 'ignore' });
  const fd = child.stdout?._handle?.fd;
  if (!Number.isInteger(fd)) {
    child.kill('SIGTERM');
    return ['error', 5];
  }
  const buffer = Buffer.alloc(6);
  const deadline = performance.now() + 250;
  let amount = 0;
  while (amount < buffer.byteLength && performance.now() < deadline) {
    try {
      const read = readSync(fd, buffer, amount, buffer.byteLength - amount, null);
      if (read === 0) break;
      amount += read;
    } catch (error) {
      if (error?.code !== 'EAGAIN') {
        child.kill('SIGTERM');
        return ['error', errnoOf(error)];
      }
      sleep(5);
    }
  }
  if (buffer.subarray(0, amount).toString() !== 'locked') {
    try { child.stdin.end(); } catch {}
    child.kill('SIGTERM');
    return ['error', 11];
  }
  const descriptor = nextDescriptor++;
  locks.set(descriptor, child);
  return ['ok', descriptor];
}

function unlock(descriptor) {
  const child = locks.get(descriptor);
  if (!child) return;
  locks.delete(descriptor);
  try { child.stdin.end(); } catch {}
  child.kill('SIGTERM');
}

function spawnStdout(argv) {
  const scratch = mkdtempSync(join(tmpdir(), 'firn-activity-child.'));
  const pidPath = join(scratch, 'pid');
  const child = spawn('setsid', [
    '-f', 'sh', '-c', 'printf "%s\\n" "$$" >"$1"; shift; exec "$@"',
    'activity-event', pidPath, ...argv,
  ], { stdin: 'ignore', stdout: 'pipe', stderr: 'inherit' });
  const fd = child.stdout?._handle?.fd;
  if (!Number.isInteger(fd)) {
    child.kill('SIGTERM');
    rmSync(scratch, { recursive: true, force: true });
    return ['error', 5];
  }
  const deadline = performance.now() + 250;
  let pid = 0;
  while (performance.now() < deadline) {
    try {
      pid = Number(readFileSync(pidPath, 'utf8').trim());
      if (Number.isSafeInteger(pid) && pid > 1) break;
    } catch {}
    sleep(5);
  }
  rmSync(scratch, { recursive: true, force: true });
  if (!Number.isSafeInteger(pid) || pid <= 1) {
    child.kill('SIGTERM');
    return ['error', 5];
  }
  const descriptor = nextDescriptor++;
  descriptors.set(descriptor, { fd, child, buffer: Buffer.alloc(0), eof: false });
  return ['ok', pid, descriptor];
}

function pump(entry, limit) {
  if (entry.eof) return;
  const chunk = Buffer.alloc(Math.min(65_536, limit + 1));
  try {
    const amount = readSync(entry.fd, chunk, 0, chunk.byteLength, null);
    if (amount === 0) {
      if (!entry.fifo) entry.eof = true;
    }
    else entry.buffer = Buffer.concat([entry.buffer, chunk.subarray(0, amount)]);
  } catch (error) {
    if (error?.code !== 'EAGAIN') entry.error = errnoOf(error);
  }
}

function readLineDeadline(descriptor, limit, timeoutMilliseconds) {
  const entry = descriptors.get(descriptor);
  if (!entry) return ['error', 9];
  const deadline = performance.now() + timeoutMilliseconds;
  while (performance.now() <= deadline) {
    pump(entry, limit);
    if (entry.error) return ['error', entry.error];
    if (entry.buffer.byteLength > limit) return ['error', 27];
    const newline = entry.buffer.indexOf(10);
    if (newline >= 0) {
      const line = decoder.decode(entry.buffer.subarray(0, newline));
      entry.buffer = entry.buffer.subarray(newline + 1);
      return ['ok', line, false];
    }
    if (entry.eof) {
      if (entry.buffer.byteLength === 0) return ['ok', '', true];
      const line = decoder.decode(entry.buffer);
      entry.buffer = Buffer.alloc(0);
      return ['ok', line, false];
    }
    sleep(5);
  }
  return ['error', 110];
}

function pollReadable(ids, timeoutMilliseconds) {
  const deadline = performance.now() + timeoutMilliseconds;
  while (performance.now() <= deadline) {
    for (const id of ids) {
      const entry = descriptors.get(id);
      if (!entry) return -9;
      pump(entry, 16 * 1024 * 1024);
      if (entry.error) return -entry.error;
      if (entry.buffer.indexOf(10) >= 0 || entry.eof) return id;
    }
    sleep(5);
  }
  return -110;
}

function fifoOpenRead(path) {
  try {
    const fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK);
    const descriptor = nextDescriptor++;
    descriptors.set(descriptor,
      { fd, child: null, buffer: Buffer.alloc(0), eof: false, fifo: true });
    return descriptor;
  } catch (error) {
    return -errnoOf(error);
  }
}

function fifoWriteDeadline(path, text, timeoutMilliseconds) {
  const deadline = performance.now() + timeoutMilliseconds;
  while (performance.now() <= deadline) {
    let fd = -1;
    try {
      fd = openSync(path, constants.O_WRONLY | constants.O_NONBLOCK);
      writeSync(fd, text);
      closeSync(fd);
      return 0;
    } catch (error) {
      if (fd >= 0) closeSync(fd);
      if (error?.code !== 'ENXIO' && error?.code !== 'EAGAIN') {
        return -errnoOf(error);
      }
      sleep(5);
    }
  }
  return -110;
}

function closeDescriptor(descriptor) {
  const entry = descriptors.get(descriptor);
  if (!entry) return -9;
  descriptors.delete(descriptor);
  try {
    if (entry.child) entry.child.stdout.destroy();
    else closeSync(entry.fd);
    return 0;
  } catch (error) {
    return -errnoOf(error);
  }
}

globalThis.activity_host_get = (value, index) => value?.[index];
globalThis.activity_host_call = (operation, args) => {
  switch (operation) {
    case 'env': return process.env[args[0]] ?? null;
    case 'stdout': process.stdout.write(args[0]); return null;
    case 'stderr': process.stderr.write(args[0]); return null;
    case 'read-text-bounded': return readTextBounded(args[0], args[1]);
    case 'write-text-atomic': return atomicWrite(args[0], args[1]);
    case 'make-parent-directories':
      try { mkdirSync(dirname(args[0]), { recursive: true }); return ['ok']; }
      catch (error) { return ['error', errnoOf(error)]; }
    case 'path-kind':
      try {
        const stat = lstatSync(args[0]);
        return ['ok', stat.isFIFO() ? 4 : (stat.isDirectory() ? 2 : 1)];
      } catch (error) { return ['error', errnoOf(error)]; }
    case 'lock-exclusive': return lockExclusive(args[0]);
    case 'unlock': unlock(args[0]); return null;
    case 'capture': {
      const result = spawnSync(args[0][0], args[0].slice(1), {
        encoding: 'utf8', env: process.env, input: args[1], maxBuffer: args[2],
      });
      return result.error
        ? ['error', errnoOf(result.error)]
        : ['ok', result.status ?? 1, result.stdout ?? '', result.stderr ?? ''];
    }
    case 'wall-nanoseconds': return Date.now() * 1_000_000;
    case 'current-pid': return process.pid;
    case 'alive': return alive(args[0]);
    case 'signal':
      try { process.kill(args[0], args[1]); return 0; }
      catch (error) { return -errnoOf(error); }
    case 'wait-not-alive': {
      const deadline = performance.now() + args[1];
      while (alive(args[0]) && performance.now() <= deadline) sleep(5);
      return alive(args[0]) ? -110 : 0;
    }
    case 'fifo-create': {
      const result = spawnSync('mkfifo', ['--mode=600', args[0]]);
      return result.error ? -errnoOf(result.error) : (result.status ?? 1);
    }
    case 'fifo-open-read': return fifoOpenRead(args[0]);
    case 'fifo-write-deadline':
      return fifoWriteDeadline(args[0], args[1], args[2]);
    case 'spawn-stdout': return spawnStdout(args[0]);
    case 'read-line-deadline': return readLineDeadline(args[0], args[1], args[2]);
    case 'poll-readable': return pollReadable(args[0], args[1]);
    case 'close': return closeDescriptor(args[0]);
    case 'wait': return alive(args[0]) ? -110 : 0;
    case 'sleep': sleep(args[0]); return null;
    default: throw new Error(`unknown activity host operation: ${operation}`);
  }
};

const modulePath = process.env.FIRN_ACTIVITY_MODULE
  ?? new URL('../lib/firn-activity/activity/native.js', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(Bun.argv.slice(2));
