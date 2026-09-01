import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { cpus } from 'node:os';
import { join } from 'node:path';

import * as policy from './machine-capacity-logic.js';

const admissionDecision = policy['admission-decision'];
const resourceClass = policy['resource-class'];
const classNames = new Set(['agent', 'moderate', 'heavy', 'exclusive']);
const maximumTimeoutSeconds = 3600;
const lockStaleMilliseconds = 2000;
const runLeaseGraceMilliseconds = 5000;

function fail(message, status = 2) {
  process.stderr.write(`machine-capacity: ${message}\n`);
  process.exit(status);
}

function parsePositiveInteger(text, option, maximum = Number.MAX_SAFE_INTEGER) {
  const value = Number(text);
  if (!Number.isSafeInteger(value) || value < 1 || value > maximum) {
    fail(`${option} must be an integer from 1 to ${maximum}`);
  }
  return value;
}

function parseNonnegativeInteger(text, option) {
  const value = Number(text);
  if (!Number.isSafeInteger(value) || value < 0) {
    fail(`${option} must be a nonnegative integer`);
  }
  return value;
}

function parseKeyValues(argv, start, allowed) {
  const values = new Map();
  let separator = argv.length;
  for (let index = start; index < argv.length; index += 2) {
    if (argv[index] === '--') {
      separator = index;
      break;
    }
    const option = argv[index];
    const value = argv[index + 1];
    if (!option?.startsWith('--') || value === undefined) {
      fail(`invalid argument at position ${index + 1}`);
    }
    if (!allowed.has(option)) fail(`unknown option: ${option}`);
    if (values.has(option)) fail(`duplicate option: ${option}`);
    values.set(option, value);
  }
  return { values, separator };
}

function required(values, option) {
  const value = values.get(option);
  if (!value) fail(`missing ${option}`);
  return value;
}

function parseClass(values, cores) {
  const name = required(values, '--class');
  if (!classNames.has(name)) fail('--class must be agent, moderate, heavy, or exclusive');
  const resources = resourceClass(name, cores);
  if (!Array.isArray(resources) || resources.length !== 2) {
    fail(`policy rejected resource class: ${name}`);
  }
  return { name, cpus: resources[0], memoryMiB: resources[1] };
}

function parsePsi(path, kind) {
  const line = readFileSync(path, 'utf8').split('\n').find(value => value.startsWith(`${kind} `));
  const match = line?.match(/avg10=([0-9]+(?:\.[0-9]+)?)/);
  if (!match) fail(`cannot read ${kind} avg10 from ${path}`);
  return Math.round(Number(match[1]) * 100);
}

function readSignals() {
  const fields = new Map();
  for (const line of readFileSync('/proc/meminfo', 'utf8').split('\n')) {
    const match = line.match(/^(MemTotal|MemAvailable):\s+([0-9]+) kB$/);
    if (match) fields.set(match[1], Math.floor(Number(match[2]) / 1024));
  }
  if (!fields.has('MemTotal') || !fields.has('MemAvailable')) {
    fail('cannot read MemTotal and MemAvailable from /proc/meminfo');
  }
  return {
    cores: cpus().length,
    memoryTotalMiB: fields.get('MemTotal'),
    memoryAvailableMiB: fields.get('MemAvailable'),
    cpuSomeAvg10BasisPoints: parsePsi('/proc/pressure/cpu', 'some'),
    memoryFullAvg10BasisPoints: parsePsi('/proc/pressure/memory', 'full'),
  };
}

function runtimeRoot() {
  const base = process.env.XDG_RUNTIME_DIR ?? `/run/user/${process.getuid()}`;
  if (!base.startsWith('/')) fail('XDG_RUNTIME_DIR must be absolute');
  return join(base, 'agent-capacity-v1');
}

function ensureState(root) {
  mkdirSync(join(root, 'leases'), { recursive: true, mode: 0o700 });
}

function withLock(root, action) {
  ensureState(root);
  const lock = join(root, 'lock');
  for (let attempt = 0; attempt < 12; attempt += 1) {
    try {
      mkdirSync(lock, { mode: 0o700 });
      try {
        return action();
      } finally {
        rmSync(lock, { recursive: true, force: true });
      }
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      if (existsSync(lock) && Date.now() - statSync(lock).mtimeMs > lockStaleMilliseconds) {
        rmSync(lock, { recursive: true, force: true });
        continue;
      }
      Bun.sleepSync(5);
    }
  }
  fail('shared admission lock remained busy', 75);
}

function readLeases(root, now) {
  const directory = join(root, 'leases');
  let reclaimed = 0;
  const active = [];
  for (const name of readdirSync(directory)) {
    if (!name.endsWith('.json')) continue;
    const path = join(directory, name);
    let lease;
    try {
      lease = JSON.parse(readFileSync(path, 'utf8'));
    } catch {
      fail(`malformed helper-owned lease: ${path}`);
    }
    if (!Number.isSafeInteger(lease.expiresAt) || lease.expiresAt <= now) {
      unlinkSync(path);
      reclaimed += 1;
      continue;
    }
    active.push(lease);
  }
  return { active, reclaimed };
}

function totals(leases) {
  return leases.reduce((sum, lease) => ({
    cpus: sum.cpus + lease.cpus,
    memoryMiB: sum.memoryMiB + lease.memoryMiB,
  }), { cpus: 0, memoryMiB: 0 });
}

function decision(root, requested, create) {
  return withLock(root, () => {
    const now = Date.now();
    const { active, reclaimed } = readLeases(root, now);
    const leased = totals(active);
    const signals = readSignals();
    const code = admissionDecision(
      signals.cores,
      signals.memoryTotalMiB,
      signals.memoryAvailableMiB,
      signals.cpuSomeAvg10BasisPoints,
      signals.memoryFullAvg10BasisPoints,
      leased.cpus,
      leased.memoryMiB,
      requested.cpus,
      requested.memoryMiB,
    );
    const result = {
      decision: code === 'RUN' ? (create ? 'RESERVED' : 'RUN') : 'DEFER',
      reason: code,
      class: requested.name,
      requestedCpus: requested.cpus,
      requestedMemoryMiB: requested.memoryMiB,
      leasedCpus: leased.cpus,
      leasedMemoryMiB: leased.memoryMiB,
      cpuSomeAvg10: signals.cpuSomeAvg10BasisPoints / 100,
      memoryFullAvg10: signals.memoryFullAvg10BasisPoints / 100,
      memoryAvailableMiB: signals.memoryAvailableMiB,
      reclaimed,
    };
    if (code !== 'RUN' || !create) return result;
    const id = crypto.randomUUID();
    const lease = {
      schema: 'agent-capacity-lease/v1',
      id,
      kind: create.kind,
      owner: create.owner,
      cpus: requested.cpus,
      memoryMiB: requested.memoryMiB,
      createdAt: now,
      expiresAt: now + create.timeoutSeconds * 1000
        + (create.kind === 'run' ? runLeaseGraceMilliseconds : 0),
    };
    writeFileSync(join(root, 'leases', `${id}.json`), `${JSON.stringify(lease)}\n`, {
      encoding: 'utf8',
      mode: 0o600,
      flag: 'wx',
    });
    return { ...result, lease: id, expiresAt: lease.expiresAt };
  });
}

function exactLease(root, id) {
  if (!/^[0-9a-f-]{36}$/.test(id)) fail('invalid lease identity');
  return join(root, 'leases', `${id}.json`);
}

function changeLease(root, id, owner, timeoutSeconds) {
  return withLock(root, () => {
    const path = exactLease(root, id);
    if (!existsSync(path)) fail(`unknown or expired lease: ${id}`, 75);
    const lease = JSON.parse(readFileSync(path, 'utf8'));
    if (lease.owner !== owner) fail(`lease owner mismatch: ${id}`);
    if (timeoutSeconds === null) {
      unlinkSync(path);
      return { decision: 'RELEASED', lease: id };
    }
    if (lease.expiresAt <= Date.now()) {
      unlinkSync(path);
      fail(`lease already expired: ${id}`, 75);
    }
    lease.expiresAt = Date.now() + timeoutSeconds * 1000;
    writeFileSync(path, `${JSON.stringify(lease)}\n`, { encoding: 'utf8', mode: 0o600 });
    return { decision: 'RENEWED', lease: id, expiresAt: lease.expiresAt };
  });
}

function print(result, stream = process.stdout) {
  stream.write(`${JSON.stringify(result)}\n`);
}

function parseOwner(values) {
  const owner = required(values, '--owner');
  if (!/^[A-Za-z0-9_.:@/-]{1,160}$/.test(owner)) {
    fail('--owner must be a stable actor label without whitespace');
  }
  return owner;
}

async function runScoped(root, requested, owner, timeoutSeconds, command) {
  const admitted = decision(root, requested, { kind: 'run', owner, timeoutSeconds });
  print(admitted, process.stderr);
  if (admitted.decision !== 'RESERVED') return 75;
  const unit = `agent-capacity-${admitted.lease.replaceAll('-', '')}.scope`;
  try {
    const child = Bun.spawn([
      'systemd-run', '--user', '--scope', '--quiet', '--collect',
      `--unit=${unit}`,
      `--property=CPUQuota=${requested.cpus * 100}%`,
      `--property=MemoryHigh=${requested.memoryMiB}M`,
      `--property=RuntimeMaxSec=${timeoutSeconds}s`,
      '--property=KillMode=control-group',
      '--', ...command,
    ], { stdin: 'inherit', stdout: 'inherit', stderr: 'inherit' });
    const stop = () => {
      Bun.spawnSync(['systemctl', '--user', 'stop', unit], {
        stdin: 'ignore', stdout: 'ignore', stderr: 'ignore',
      });
    };
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
    return await child.exited;
  } finally {
    try {
      changeLease(root, admitted.lease, owner, null);
    } catch (error) {
      process.stderr.write(`machine-capacity: lease cleanup failed: ${error?.message ?? String(error)}\n`);
    }
  }
}

async function main(argv) {
  const operation = argv[0];
  if (operation === 'fixture') {
    const parsed = parseKeyValues(argv, 1, new Set([
      '--class', '--cores', '--memory-total-mib', '--memory-available-mib',
      '--cpu-some-avg10-basis-points', '--memory-full-avg10-basis-points',
      '--leased-cpus', '--leased-memory-mib',
    ]));
    if (parsed.separator !== argv.length) fail('fixture accepts no command');
    const cores = parsePositiveInteger(required(parsed.values, '--cores'), '--cores');
    const requested = parseClass(parsed.values, cores);
    const code = admissionDecision(
      cores,
      parsePositiveInteger(required(parsed.values, '--memory-total-mib'), '--memory-total-mib'),
      parsePositiveInteger(required(parsed.values, '--memory-available-mib'), '--memory-available-mib'),
      parseNonnegativeInteger(required(parsed.values, '--cpu-some-avg10-basis-points'), '--cpu-some-avg10-basis-points'),
      parseNonnegativeInteger(required(parsed.values, '--memory-full-avg10-basis-points'), '--memory-full-avg10-basis-points'),
      parseNonnegativeInteger(required(parsed.values, '--leased-cpus'), '--leased-cpus'),
      parseNonnegativeInteger(required(parsed.values, '--leased-memory-mib'), '--leased-memory-mib'),
      requested.cpus,
      requested.memoryMiB,
    );
    print({ decision: code, class: requested.name, cpus: requested.cpus, memoryMiB: requested.memoryMiB });
    return code === 'RUN' ? 0 : 75;
  }
  const root = runtimeRoot();
  if (operation === 'probe') {
    const { values, separator } = parseKeyValues(argv, 1, new Set(['--class']));
    if (separator !== argv.length) fail('probe accepts no command');
    const signals = readSignals();
    const result = decision(root, parseClass(values, signals.cores), null);
    print(result);
    return result.decision === 'RUN' ? 0 : 75;
  }
  if (operation === 'reserve') {
    const parsed = parseKeyValues(argv, 1, new Set(['--class', '--owner', '--timeout-seconds']));
    if (parsed.separator !== argv.length) fail('reserve accepts no command');
    const signals = readSignals();
    const requested = parseClass(parsed.values, signals.cores);
    const owner = parseOwner(parsed.values);
    const timeoutSeconds = parsePositiveInteger(
      required(parsed.values, '--timeout-seconds'), '--timeout-seconds', maximumTimeoutSeconds,
    );
    const result = decision(root, requested, { kind: 'agent', owner, timeoutSeconds });
    print(result);
    return result.decision === 'RESERVED' ? 0 : 75;
  }
  if (operation === 'renew' || operation === 'release') {
    const allowed = operation === 'renew'
      ? new Set(['--lease', '--owner', '--timeout-seconds'])
      : new Set(['--lease', '--owner']);
    const parsed = parseKeyValues(argv, 1, allowed);
    if (parsed.separator !== argv.length) fail(`${operation} accepts no command`);
    const timeoutSeconds = operation === 'renew'
      ? parsePositiveInteger(required(parsed.values, '--timeout-seconds'), '--timeout-seconds', maximumTimeoutSeconds)
      : null;
    print(changeLease(
      root,
      required(parsed.values, '--lease'),
      parseOwner(parsed.values),
      timeoutSeconds,
    ));
    return 0;
  }
  if (operation === 'run') {
    const parsed = parseKeyValues(argv, 1, new Set(['--class', '--owner', '--timeout-seconds']));
    const command = argv.slice(parsed.separator + 1);
    if (parsed.separator === argv.length || command.length === 0) fail('run requires -- COMMAND ARG...');
    const signals = readSignals();
    const requested = parseClass(parsed.values, signals.cores);
    return runScoped(
      root,
      requested,
      parseOwner(parsed.values),
      parsePositiveInteger(required(parsed.values, '--timeout-seconds'), '--timeout-seconds', maximumTimeoutSeconds),
      command,
    );
  }
  fail('usage: probe|reserve|renew|release|run; see machine-capacity-distilled');
}

process.exitCode = await main(Bun.argv.slice(2));
