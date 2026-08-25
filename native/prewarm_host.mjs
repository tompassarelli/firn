// SPDX-License-Identifier: MIT OR Apache-2.0

import {
  closeSync,
  constants,
  existsSync,
  fsyncSync,
  lstatSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { hostname, platform } from 'node:os';

const modulePath = process.env.FIRN_PREWARM_MODULE
  ?? new URL('../lib/firn-prewarm.js', import.meta.url).pathname;
const policy = await import(modulePath);
const call = (name, ...args) => policy[name](...args);
const maxOutput = 16 * 1024 * 1024;
const maxCmdline = 1024 * 1024;
const attempts = 100;
const retryMilliseconds = 50;

if (Bun.argv[2] === '--lock-holder') {
  process.stdout.write('locked\n');
  for await (const _ of Bun.stdin.stream()) { /* hold until owner closes stdin */ }
  process.exit(0);
}

function scrubbedGit(arguments_) {
  const env = { ...process.env };
  for (const name of [
    'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CONFIG',
    'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_COUNT', 'GIT_OBJECT_DIRECTORY',
    'GIT_DIR', 'GIT_WORK_TREE', 'GIT_IMPLICIT_WORK_TREE', 'GIT_GRAFT_FILE',
    'GIT_INDEX_FILE', 'GIT_NO_REPLACE_OBJECTS', 'GIT_REPLACE_REF_BASE',
    'GIT_PREFIX', 'GIT_SHALLOW_FILE', 'GIT_COMMON_DIR',
  ]) delete env[name];
  return Bun.spawnSync({ cmd: ['git', ...arguments_], env, stdout: 'pipe', stderr: 'pipe' });
}

function captureGit(arguments_) {
  const result = scrubbedGit(arguments_);
  if (result.exitCode !== 0 || result.stdout.byteLength > maxOutput) return null;
  return new TextDecoder().decode(result.stdout).replace(/[\r\n]+$/u, '');
}

function kind(path) {
  try {
    const stat = lstatSync(path);
    if (stat.isDirectory()) return 2;
    if (stat.isFile() || stat.isSymbolicLink()) return 1;
    return 0;
  } catch { return 0; }
}

function looksLikeFirn(path) {
  return kind(path) === 2
    && kind(`${path}/native/firn.bjs`) === 1
    && kind(`${path}/flake.bnix`) === 1;
}

function resolveRepository() {
  const candidate = process.env.FIRN_REPO
    ?? (process.env.HOME ? `${process.env.HOME}/code/nixos-config/main` : null);
  if (!candidate) return null;
  const common = captureGit(['-C', candidate, 'rev-parse',
    '--path-format=absolute', '--git-common-dir']);
  for (const path of call('container-main-candidates', candidate, common)) {
    if (looksLikeFirn(path)) return path;
  }
  return null;
}

function configuredHost(repository) {
  const full = hostname();
  if (kind(`${repository}/hosts/${full}`) === 2) return full;
  const short = call('short-host', full);
  return kind(`${repository}/hosts/${short}`) === 2 ? short : null;
}

function resolveWarm() {
  const repository = resolveRepository();
  if (!repository) return null;
  const revision = captureGit(['-C', repository, 'rev-parse', 'HEAD']);
  const branch = captureGit(['-C', repository, 'branch', '--show-current']);
  const host = configuredHost(repository);
  if (revision === null || branch === null || !host) return null;
  const system = platform() === 'darwin' ? 'darwin' : 'linux';
  return { repository, key: call('warm-key', repository, revision, branch, host, system) };
}

function readOptional(path, bound = maxOutput) {
  try {
    const value = readFileSync(path);
    return value.byteLength <= bound ? new TextDecoder().decode(value) : null;
  } catch (error) {
    return error?.code === 'ENOENT' ? '' : null;
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
    return true;
  } catch {
    if (descriptor >= 0) closeSync(descriptor);
    try { unlinkSync(temporary); } catch {}
    return false;
  }
}

function processArgv(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return [];
  const text = readOptional(`/proc/${pid}/cmdline`, maxCmdline);
  return text === null ? [] : call('command-argv', text);
}

function alive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; } catch { return false; }
}

async function waitNotAlive(pid, milliseconds) {
  const deadline = performance.now() + milliseconds;
  while (alive(pid) && performance.now() < deadline) await Bun.sleep(10);
  return !alive(pid);
}

function rebuildRunning() {
  if (platform() !== 'linux') return false;
  for (const name of readdirSync('/proc').slice(0, 131072)) {
    if (!/^\d+$/u.test(name) || Number(name) === process.pid) continue;
    if (call('rebuild-argv?', processArgv(Number(name)))) return true;
  }
  return false;
}

async function acquireLease(path) {
  let child;
  try {
    child = Bun.spawn(['flock', '--exclusive', '--nonblock',
      '--conflict-exit-code', '73', path, process.execPath,
      import.meta.path, '--lock-holder'], {
      stdin: 'pipe', stdout: 'pipe', stderr: 'ignore',
    });
    const reader = child.stdout.getReader();
    const first = await reader.read();
    if (first.done || new TextDecoder().decode(first.value) !== 'locked\n') {
      await child.exited;
      return null;
    }
    return { child, reader };
  } catch {
    if (child) child.kill('SIGTERM');
    return null;
  }
}

async function releaseLease(lease) {
  try { lease.child.stdin.end(); } catch {}
  await lease.child.exited;
  try { await lease.reader.cancel(); } catch {}
}

async function signalExact(pid, expected) {
  if (pid <= 0 || pid === process.pid || !alive(pid)) return false;
  if (JSON.stringify(processArgv(pid)) !== JSON.stringify(expected)) return false;
  try { process.kill(pid, 'SIGTERM'); return true; } catch { return false; }
}

async function contention(ownerPath, desiredKey, executable, repository) {
  const ownerText = readOptional(ownerPath);
  if (ownerText === null) return ['contended'];
  const fields = call('parsed-owner-fields', ownerText);
  if (fields.length !== 3) return ['contended'];
  const workerPid = Number(fields[0]);
  const childPid = Number(fields[1]);
  const action = call('supersede-action', desiredKey, process.pid, executable,
    repository, ownerText, processArgv(workerPid), processArgv(childPid));
  if (action[0] !== 'supersede') return action;
  const key = fields[2];
  const childSignaled = await signalExact(childPid, call('nix-build-argv', key));
  const childDead = childSignaled && await waitNotAlive(childPid, 1000);
  let workerDead = await waitNotAlive(workerPid, 1000);
  if (!workerDead) {
    const workerSignaled = await signalExact(workerPid,
      call('worker-argv', executable, repository, key));
    workerDead = workerSignaled && await waitNotAlive(workerPid, 250);
  }
  return childDead && workerDead ? ['superseded', key] : ['contended'];
}

async function runBuild(ownerPath, stampPath, key) {
  if (call('stamp-current?', readOptional(stampPath) ?? '', key)
      || rebuildRunning()) return 0;
  let child;
  let cancelled = false;
  const cancel = () => {
    cancelled = true;
    if (child) child.kill('SIGTERM');
  };
  process.once('SIGTERM', cancel);
  process.once('SIGINT', cancel);
  try {
    child = Bun.spawn(call('nix-build-argv', key), {
      stdin: 'ignore', stdout: 'pipe', stderr: 'inherit',
    });
    if (!atomicWrite(ownerPath,
      call('render-owner', process.pid, child.pid, key))) {
      child.kill('SIGTERM');
    }
    let amount = 0;
    for await (const chunk of child.stdout) {
      amount += chunk.byteLength;
      if (amount > maxOutput) child.kill('SIGTERM');
    }
    const status = await child.exited;
    if (!cancelled && amount <= maxOutput && status === 0) atomicWrite(stampPath, `${key}\n`);
    return status;
  } catch { return 0; }
  finally {
    process.off('SIGTERM', cancel);
    process.off('SIGINT', cancel);
  }
}

async function runWorker(executable, repository, key) {
  const state = process.env.XDG_RUNTIME_DIR;
  if (!state || kind(state) !== 2 || platform() !== 'linux') return 0;
  const leasePath = `${state}/firn-prewarm.lease`;
  const ownerPath = `${state}/firn-prewarm.owner`;
  const stampPath = `${state}/firn-prewarm.warm`;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const lease = await acquireLease(leasePath);
    if (lease) {
      try { return await runBuild(ownerPath, stampPath, key); }
      finally { atomicWrite(ownerPath, '0\n0\n\n'); await releaseLease(lease); }
    }
    const action = await contention(ownerPath, key, executable, repository);
    if (action[0] === 'deduplicated') return 0;
    await Bun.sleep(retryMilliseconds);
  }
  return 0;
}

function emit(argv) { for (const value of argv) process.stdout.write(`${value}\n`); }

async function main(args) {
  if (args.length === 1 && args[0] === '--print-warm-key') {
    const warm = resolveWarm();
    if (!warm) return 1;
    process.stdout.write(`${warm.key}\n`);
    return 0;
  }
  if (args.length === 2 && args[0] === '--plan-detached') {
    const warm = resolveWarm();
    if (!warm) return 1;
    emit(call('detached-worker-argv', args[1], warm.repository, warm.key));
    return 0;
  }
  if (args.length >= 3 && (args[0] === '--plan-reference-transaction'
      || args[0] === '--reference-transaction')) {
    const warm = resolveWarm();
    if (!warm) return 0;
    const argv = call('hook-argv-or-empty', args[2], args.slice(3), args[1],
      warm.repository, warm.key);
    if (args[0] === '--plan-reference-transaction') emit(argv);
    else if (argv.length > 0) Bun.spawnSync({ cmd: argv, stdin: 'inherit', stdout: 'inherit', stderr: 'inherit' });
    return 0;
  }
  if (args.length === 4 && args[0] === '--worker') return runWorker(args[1], args[2], args[3]);
  process.stderr.write('usage: firn --print-warm-key\n'
    + '       firn --plan-detached <self>\n'
    + '       firn --plan-reference-transaction <self> <state> [line ...]\n'
    + '       firn --reference-transaction <self> <state> [line ...]\n'
    + '       firn --worker <self> <repository> <key>\n');
  return 64;
}

process.exitCode = await main(Bun.argv.slice(2));
