#!/usr/bin/env bun

import { once } from 'node:events';
import { accessSync, constants, createReadStream, write as writeDescriptor } from 'node:fs';
import { spawn } from 'node:child_process';
import { dlopen, FFIType, ptr } from 'bun:ffi';

const HANDSHAKE_CAP = 4096;
const CONTROL_CAP = 1024 * 1024;
const EXCHANGE_TIMEOUT_MS = 2000;
const CONTROL_FD = 3;
const CONTROL_FD_ENV = 'CODEX_CONTROL_EXPECTATION_FD';
const SIGNALS = Object.freeze(['SIGINT', 'SIGTERM', 'SIGHUP', 'SIGQUIT']);
const SIGNAL_EXIT = Object.freeze({ SIGHUP: 129, SIGINT: 130, SIGQUIT: 131, SIGTERM: 143 });
const AF_UNIX = 1;
const SOCK_STREAM = 1;
const F_GETFD = 1;
const F_SETFD = 2;
const F_GETFL = 3;
const F_SETFL = 4;
const FD_CLOEXEC = 1;
const O_NONBLOCK = 0o4000;

const libc = dlopen('libc.so.6', {
  socketpair: {
    args: [FFIType.i32, FFIType.i32, FFIType.i32, FFIType.ptr],
    returns: FFIType.i32,
  },
  fcntl: {
    args: [FFIType.i32, FFIType.i32, FFIType.i32],
    returns: FFIType.i32,
  },
  close: { args: [FFIType.i32], returns: FFIType.i32 },
});

const modulePath = process.env.CODEX_INVOCATION_CONTROLLER_MODULE
  ?? new URL('../lib/codex-invocation-controller/firn/codex-invocation-controller.js',
    import.meta.url).pathname;
const protocol = await import(modulePath);
const validateHandshake = protocol['validate-handshake'];
const renderHandshakeResponse = protocol['render-handshake-response'];
const validateRequest = protocol['validate-request'];
const renderNoExpectation = protocol['render-no-expectation'];

if ([validateHandshake, renderHandshakeResponse, validateRequest, renderNoExpectation]
  .some(operation => typeof operation !== 'function')) {
  throw new Error('codex invocation controller: typed protocol module is incomplete');
}

function checkedFcntl(descriptor, operation, value) {
  const result = libc.symbols.fcntl(descriptor, operation, value);
  if (result === -1) throw new Error('codex invocation controller: fcntl failed');
  return result;
}

function closeDescriptor(descriptor) {
  if (descriptor >= 0) libc.symbols.close(descriptor);
}

function connectedUnixEndpoints() {
  const descriptors = new Int32Array(2);
  if (libc.symbols.socketpair(AF_UNIX, SOCK_STREAM, 0, ptr(descriptors)) !== 0) {
    throw new Error('codex invocation controller: socketpair failed');
  }
  try {
    for (const descriptor of descriptors) {
      const descriptorFlags = checkedFcntl(descriptor, F_GETFD, 0);
      checkedFcntl(descriptor, F_SETFD, descriptorFlags | FD_CLOEXEC);
    }
    const inheritedFlags = checkedFcntl(descriptors[1], F_GETFL, 0);
    checkedFcntl(descriptors[1], F_SETFL, inheritedFlags & ~O_NONBLOCK);
    const controllerFlags = checkedFcntl(descriptors[0], F_GETFL, 0);
    checkedFcntl(descriptors[0], F_SETFL, controllerFlags & ~O_NONBLOCK);
    const controller = createReadStream('', {
      fd: descriptors[0],
      autoClose: false,
    });
    return {
      controller,
      controllerDescriptor: descriptors[0],
      inherited: descriptors[1],
    };
  } catch (error) {
    closeDescriptor(descriptors[0]);
    closeDescriptor(descriptors[1]);
    throw error;
  }
}

function encodeFrame(text, maximum) {
  const payload = Buffer.from(text, 'utf8');
  if (payload.byteLength === 0 || payload.byteLength > maximum) {
    throw new Error('codex invocation controller: typed response exceeded its frame cap');
  }
  const frame = Buffer.allocUnsafe(payload.byteLength + 4);
  frame.writeUInt32BE(payload.byteLength, 0);
  payload.copy(frame, 4);
  return frame;
}

class ProtocolChannel {
  constructor(input, descriptor, child, onFailure) {
    this.input = input;
    this.descriptor = descriptor;
    this.child = child;
    this.onFailure = onFailure;
    this.phase = 'handshake';
    this.buffer = Buffer.alloc(0);
    this.pendingWrite = false;
    this.timer = null;
    this.closedForChildExit = false;
    this.failed = false;
    this.requestIds = new Set();
    input.on('data', chunk => this.receive(chunk));
    input.on('end', () => this.channelClosed());
    input.on('close', () => this.channelClosed());
    input.on('error', error => this.fail(`socket error ${error?.code ?? 'unknown'}`));
    this.armTimeout();
  }

  armTimeout() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fail('exchange timeout'), EXCHANGE_TIMEOUT_MS);
  }

  clearTimeout() {
    clearTimeout(this.timer);
    this.timer = null;
  }

  receive(chunk) {
    if (this.failed || this.closedForChildExit) return;
    if (this.pendingWrite) {
      this.fail('out-of-order frame during response');
      return;
    }
    this.buffer = this.buffer.byteLength === 0
      ? Buffer.from(chunk)
      : Buffer.concat([this.buffer, chunk]);
    this.armTimeout();
    this.consume();
  }

  consume() {
    if (this.buffer.byteLength < 4) return;
    const maximum = this.phase === 'handshake' ? HANDSHAKE_CAP : CONTROL_CAP;
    const length = this.buffer.readUInt32BE(0);
    if (length === 0 || length > maximum) {
      this.fail('invalid frame length');
      return;
    }
    const frameLength = length + 4;
    if (this.buffer.byteLength < frameLength) return;
    if (this.buffer.byteLength !== frameLength) {
      this.fail('out-of-order pipelined frame');
      return;
    }
    const payload = this.buffer.subarray(4);
    this.buffer = Buffer.alloc(0);
    this.clearTimeout();
    let source;
    try {
      source = new TextDecoder('utf-8', { fatal: true }).decode(payload);
    } catch {
      this.fail('frame is not UTF-8');
      return;
    }
    this.handle(source, maximum);
  }

  handle(source, maximum) {
    let response;
    if (this.phase === 'handshake') {
      const challenge = validateHandshake(source, this.child.pid);
      if (challenge === '') {
        this.fail('invalid handshake challenge');
        return;
      }
      response = renderHandshakeResponse(challenge, process.pid, process.geteuid());
      if (response === '') {
        this.fail('handshake response rendering failed');
        return;
      }
    } else {
      const requestId = validateRequest(source);
      if (requestId === '') {
        this.fail('invalid invocation request');
        return;
      }
      if (this.requestIds.has(requestId)) {
        this.fail('replayed invocation request');
        return;
      }
      this.requestIds.add(requestId);
      response = renderNoExpectation(requestId);
      if (response === '') {
        this.fail('explicit-none response rendering failed');
        return;
      }
    }
    let frame;
    try { frame = encodeFrame(response, maximum); }
    catch (error) {
      this.fail(error.message);
      return;
    }
    this.pendingWrite = true;
    this.armTimeout();
    this.writeAll(frame, 0, () => {
      this.clearTimeout();
      this.pendingWrite = false;
      if (this.phase === 'handshake') this.phase = 'control';
    });
  }

  writeAll(frame, offset, complete) {
    writeDescriptor(
      this.descriptor,
      frame,
      offset,
      frame.byteLength - offset,
      null,
      (error, written) => {
        if (error || written <= 0) {
          this.fail(`response write failed ${error?.code ?? 'zero-write'}`);
          return;
        }
        const next = offset + written;
        if (next === frame.byteLength) complete();
        else this.writeAll(frame, next, complete);
      },
    );
  }

  channelClosed() {
    if (this.closedForChildExit || this.failed) return;
    const reason = this.buffer.byteLength === 0
      ? 'unexpected channel EOF'
      : 'partial frame EOF';
    setTimeout(() => {
      if (this.closedForChildExit || this.failed) return;
      if (this.child.exitCode !== null || this.child.signalCode !== null) return;
      this.fail(reason);
    }, 0);
  }

  fail(reason) {
    if (this.failed || this.closedForChildExit) return;
    this.failed = true;
    this.clearTimeout();
    this.onFailure(reason);
  }

  closeForChildExit() {
    this.closedForChildExit = true;
    this.clearTimeout();
    this.input.destroy();
  }
}

async function waitForSpawn(child) {
  if (child.pid) return;
  await Promise.race([
    once(child, 'spawn'),
    once(child, 'error').then(([error]) => { throw error; }),
  ]);
}

function waitForExit(child) {
  return new Promise(resolve => {
    let settled = false;
    const complete = (code, signal) => {
      if (settled) return;
      settled = true;
      resolve({ code, signal });
    };
    child.once('exit', complete);
    if (child.exitCode !== null || child.signalCode !== null) {
      child.off('exit', complete);
      complete(child.exitCode, child.signalCode);
    }
  });
}

async function runController(real, argv) {
  accessSync(real, constants.X_OK);
  const endpoints = connectedUnixEndpoints();
  let child;
  let channel;
  let protocolFailure = null;
  let childExited = false;
  let inheritedOpen = true;
  const signalHandlers = new Map();
  try {
    child = spawn(real, argv, {
      cwd: process.cwd(),
      env: { ...process.env, [CONTROL_FD_ENV]: String(CONTROL_FD) },
      stdio: ['inherit', 'inherit', 'inherit', endpoints.inherited],
    });
    await waitForSpawn(child);
    closeDescriptor(endpoints.inherited);
    inheritedOpen = false;

    const failure = new Promise(resolve => {
      channel = new ProtocolChannel(
        endpoints.controller,
        endpoints.controllerDescriptor,
        child,
        reason => resolve(reason),
      );
    });
    const exited = waitForExit(child);
    for (const signal of SIGNALS) {
      const handler = () => {
        if (!childExited) child.kill(signal);
      };
      signalHandlers.set(signal, handler);
      process.on(signal, handler);
    }

    const first = await Promise.race([
      exited.then(status => ({ kind: 'exit', status })),
      failure.then(reason => ({ kind: 'failure', reason })),
    ]);
    if (first.kind === 'failure') {
      protocolFailure = first.reason;
      child.kill('SIGKILL');
      await exited;
      childExited = true;
      channel.closeForChildExit();
      return { code: 70, signal: null, protocolFailure };
    }
    childExited = true;
    channel.closeForChildExit();
    return { ...first.status, protocolFailure: null };
  } finally {
    for (const [signal, handler] of signalHandlers) process.off(signal, handler);
    if (inheritedOpen) closeDescriptor(endpoints.inherited);
    try { endpoints.controller.destroy(); } catch {}
    closeDescriptor(endpoints.controllerDescriptor);
  }
}

const [real, ...argv] = Bun.argv.slice(2);
if (!real) {
  process.stderr.write('usage: codex-invocation-controller <codex> [argument ...]\n');
  process.exit(64);
}

try {
  const outcome = await runController(real, argv);
  if (outcome.protocolFailure) {
    process.stderr.write(`codex invocation controller: ${outcome.protocolFailure}\n`);
  }
  if (outcome.signal) {
    try { process.kill(process.pid, outcome.signal); }
    catch { process.exit(SIGNAL_EXIT[outcome.signal] ?? 1); }
  } else {
    process.exit(outcome.code ?? 1);
  }
} catch (error) {
  process.stderr.write(`codex invocation controller: setup failed (${error?.code ?? 'error'})\n`);
  process.exit(70);
}
