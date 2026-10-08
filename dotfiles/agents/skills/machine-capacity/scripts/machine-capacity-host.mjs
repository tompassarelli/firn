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
const nativeMemoryRequest = policy['native-memory-request'];
const reserveClass = policy['reserve-class'];
const aggregateCpus = policy['aggregate-cpus'];
const batchClass = policy['batch-class'];
const aggregateSlice = 'agent-capacity.slice';
// Sibling of session.slice (300), app.slice (100) and agent.slice (20): game
// clients outrank terminals and batch work but never the compositor.
const nativeSlice = 'native.slice';
const nativeCpuWeight = 200;
const classNames = new Set(['agent', 'native', 'moderate', 'heavy', 'exclusive']);
const modes = new Map([['present', 'attended'], ['away', 'unattended'], ['auto', null]]);
const idleSecondsForUnattended = 600;
const presenceUnit = 'agent-capacity-presence.service';
const maximumTimeoutSeconds = 3600;
const lockStaleMilliseconds = 2000;
const runLeaseGraceMilliseconds = 5000;
const queuePollMilliseconds = 1000;

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
  if (!classNames.has(name)) fail('--class must be agent, native, moderate, heavy, or exclusive');
  let resources = resourceClass(name, cores);
  if (values.has('--memory-gib')) {
    const memoryGiB = Number(required(values, '--memory-gib'));
    if (!Number.isFinite(memoryGiB)) fail('--memory-gib must be finite');
    try {
      resources = nativeMemoryRequest(name, cores, memoryGiB);
    } catch (error) {
      fail(error.message);
    }
    if (!Number.isSafeInteger(resources.memoryMiB)) {
      fail('--memory-gib must represent a whole, safe number of MiB');
    }
  }
  if (!Number.isFinite(resources.cpus) || !Number.isFinite(resources.memoryMiB)) {
    fail(`policy rejected resource class: ${name}`);
  }
  return { name, ...resources };
}

function parsePsi(path, kind) {
  const line = readFileSync(path, 'utf8').split('\n').find(value => value.startsWith(`${kind} `));
  const match = line?.match(/avg10=([0-9]+(?:\.[0-9]+)?)/);
  if (!match) fail(`cannot read ${kind} avg10 from ${path}`);
  return Math.round(Number(match[1]) * 100);
}

function userManagerCgroup() {
  return `/sys/fs/cgroup/user.slice/user-${process.getuid()}.slice/user@${process.getuid()}.service`;
}

function slicePressure(slice) {
  const path = process.env.AGENT_CAPACITY_CPU_PRESSURE ?? join(userManagerCgroup(), slice, 'cpu.pressure');
  return existsSync(path) ? parsePsi(path, 'some') : 0;
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
    // Tests record one pressure file for every reading so other load cannot hold them.
    cpuSomeAvg10BasisPoints: parsePsi(process.env.AGENT_CAPACITY_CPU_PRESSURE ?? '/proc/pressure/cpu', 'some'),
    protectedCpuSomeAvg10BasisPoints: Math.max(slicePressure('session.slice'), slicePressure(nativeSlice)),
    memoryFullAvg10BasisPoints: parsePsi('/proc/pressure/memory', 'full'),
  };
}

function runtimeRoot() {
  const base = process.env.XDG_RUNTIME_DIR ?? `/run/user/${process.getuid()}`;
  if (!base.startsWith('/')) fail('XDG_RUNTIME_DIR must be absolute');
  return join(base, 'agent-capacity-v1');
}

function readMode(root) {
  try {
    const mode = readFileSync(join(root, 'mode'), 'utf8').trim();
    return modes.has(mode) ? mode : 'auto';
  } catch (error) {
    if (error?.code === 'ENOENT') return 'auto';
    throw error;
  }
}

function idleSeconds(root) {
  try {
    return (Date.now() - statSync(join(root, 'last-input')).mtimeMs) / 1000;
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

// Without presence evidence the desktop is assumed attended.
function activeProfile(root) {
  const mode = readMode(root);
  if (modes.get(mode)) return { mode, profile: modes.get(mode), idleSeconds: idleSeconds(root) };
  const idle = idleSeconds(root);
  return {
    mode,
    profile: idle !== null && idle >= idleSecondsForUnattended ? 'unattended' : 'attended',
    idleSeconds: idle,
  };
}

function setSlice(slice, ...properties) {
  const result = Bun.spawnSync([
    'systemctl', '--user', 'set-property', '--runtime', slice, ...properties,
  ], { stdin: 'ignore', stdout: 'ignore', stderr: 'inherit' });
  return result.exitCode === 0;
}

function applyProfile(profile, cores) {
  return setSlice(aggregateSlice, `CPUQuota=${aggregateCpus(profile, cores) * 100}%`)
    && setSlice(nativeSlice, `CPUWeight=${nativeCpuWeight}`, `IOWeight=${nativeCpuWeight}`);
}

// Input devices that report keys or buttons, minus automation's virtual pads,
// which must not make an unattended machine look attended. A grabbed physical
// keyboard is silent here; its remapper's re-emitting device is read instead.
function presenceDevices() {
  const devices = [];
  for (const name of readdirSync('/sys/class/input')) {
    if (!/^event[0-9]+$/.test(name)) continue;
    try {
      const base = `/sys/class/input/${name}/device`;
      const label = readFileSync(`${base}/name`, 'utf8').trim();
      const events = Number.parseInt(readFileSync(`${base}/capabilities/ev`, 'utf8').trim(), 16);
      if ((events & 0x2) !== 0 && !/virtual/i.test(label)) devices.push(`/dev/input/${name}`);
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
  }
  return devices;
}

async function watchPresence(root) {
  ensureState(root);
  const marker = join(root, 'last-input');
  const readers = new Map();
  let applied = null;
  let lastMark = 0;
  const reconcile = () => {
    const { profile } = activeProfile(root);
    if (profile !== applied && applyProfile(profile, readSignals().cores)) {
      applied = profile;
      process.stdout.write(`${JSON.stringify({ profile, at: new Date().toISOString() })}\n`);
    }
  };
  const mark = device => {
    const now = Date.now();
    if (now - lastMark < 1000) return;
    if (now - lastMark > 60000) {
      process.stdout.write(`${JSON.stringify({ input: device, at: new Date(now).toISOString() })}\n`);
    }
    lastMark = now;
    writeFileSync(marker, '', { mode: 0o600 });
    if (applied === 'unattended') reconcile();
  };
  const rescan = () => {
    for (const device of presenceDevices()) {
      if (readers.has(device)) continue;
      const reader = Bun.spawn(['cat', device], { stdin: 'ignore', stdout: 'pipe', stderr: 'ignore' });
      readers.set(device, reader);
      (async () => {
        for await (const _ of reader.stdout) mark(device);
        readers.delete(device);
      })();
    }
  };
  // Idleness is unknown until watched: count it from the watcher's start.
  if (!existsSync(marker)) writeFileSync(marker, '', { mode: 0o600 });
  rescan();
  reconcile();
  setInterval(() => { rescan(); reconcile(); }, 5000);
  await new Promise(() => {});
}

function ensurePresenceWatcher() {
  const state = Bun.spawnSync(['systemctl', '--user', 'is-active', presenceUnit], {
    stdin: 'ignore', stdout: 'pipe', stderr: 'ignore',
  }).stdout.toString().trim();
  if (state === 'active' || state === 'activating') return;
  Bun.spawnSync([
    'systemd-run', '--user', '--quiet', '--collect', `--unit=${presenceUnit}`,
    '--slice=background.slice', '--property=Restart=on-failure',
    process.execPath, Bun.main, 'presence',
  ], { stdin: 'ignore', stdout: 'ignore', stderr: 'inherit' });
}

function ensureState(root) {
  mkdirSync(join(root, 'leases'), { recursive: true, mode: 0o700 });
  mkdirSync(join(root, 'queue'), { recursive: true, mode: 0o700 });
}

function withLock(root, action) {
  ensureState(root);
  const lock = join(root, 'lock');
  // Queued wrappers poll the lock, so allow for many short peer holds.
  for (let attempt = 0; attempt < 400; attempt += 1) {
    try {
      mkdirSync(lock, { mode: 0o700 });
      try {
        return action();
      } finally {
        rmSync(lock, { recursive: true, force: true });
      }
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      let age = 0;
      try {
        age = Date.now() - statSync(lock).mtimeMs;
      } catch (statError) {
        // The holder released it between our attempt and this check.
        if (statError?.code !== 'ENOENT') throw statError;
      }
      if (age > lockStaleMilliseconds) {
        rmSync(lock, { recursive: true, force: true });
        continue;
      }
      Bun.sleepSync(5);
    }
  }
  fail('shared admission lock remained busy', 75);
}

function processStart(pid) {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, 'utf8');
    const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
    return fields[0] === 'Z' ? null : fields[19];
  } catch (error) {
    if (error?.code === 'ENOENT' || error?.code === 'ESRCH') return null;
    throw error;
  }
}

function scopeUnit(id) {
  return `agent-capacity-${id.replaceAll('-', '')}.scope`;
}

function scopeLive(id) {
  const result = Bun.spawnSync([
    'systemctl', '--user', 'show', scopeUnit(id), '--property=ActiveState', '--value',
  ], { stdin: 'ignore', stdout: 'pipe', stderr: 'ignore' });
  const state = result.stdout.toString().trim();
  // Unknown manager state must not free a possibly live resource allowance.
  return !['inactive', 'failed'].includes(state);
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
    const liveRun = lease.kind === 'run' && lease.wrapperStart !== undefined;
    const expired = liveRun
      ? processStart(lease.wrapperPid) !== lease.wrapperStart && !scopeLive(lease.id)
      : !Number.isSafeInteger(lease.expiresAt) || lease.expiresAt <= now;
    if (expired) {
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
    cpus: sum.cpus + (lease.kind === 'run' ? lease.cpus : 0),
    batchCpus: sum.batchCpus + (lease.kind === 'run' && batchClass(lease.class) ? lease.cpus : 0),
    nativeCpus: sum.nativeCpus + (lease.kind === 'run' && lease.class === 'native' ? lease.cpus : 0),
    memoryMiB: sum.memoryMiB + lease.memoryMiB,
  }), { cpus: 0, batchCpus: 0, nativeCpus: 0, memoryMiB: 0 });
}

// Held batch wrappers wait in arrival order; a ticket whose wrapper died is dropped.
function enqueue(root) {
  ensureState(root);
  const name = `${String(Date.now()).padStart(15, '0')}-${crypto.randomUUID()}.json`;
  writeFileSync(join(root, 'queue', name), `${JSON.stringify({
    wrapperPid: process.pid, wrapperStart: processStart(process.pid),
  })}\n`, { encoding: 'utf8', mode: 0o600, flag: 'wx' });
  return name;
}

function dequeue(root, ticket) {
  try {
    unlinkSync(join(root, 'queue', ticket));
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
}

function readQueue(root) {
  const directory = join(root, 'queue');
  const waiting = [];
  for (const name of readdirSync(directory).sort()) {
    if (!name.endsWith('.json')) continue;
    let ticket;
    try {
      ticket = JSON.parse(readFileSync(join(directory, name), 'utf8'));
    } catch {
      dequeue(root, name);
      continue;
    }
    if (processStart(ticket.wrapperPid) !== ticket.wrapperStart) {
      dequeue(root, name);
      continue;
    }
    waiting.push(name);
  }
  return waiting;
}

function leaseSlice(className) {
  return className === 'native' ? nativeSlice : aggregateSlice;
}

function decision(root, requested, create, ticket = null) {
  return withLock(root, () => {
    const now = Date.now();
    const { active, reclaimed } = readLeases(root, now);
    const queue = readQueue(root);
    const queuedAhead = ticket === null ? queue.length : queue.filter(name => name < ticket).length;
    const leased = totals(active);
    const runs = active.filter(lease => lease.kind === 'run');
    const signals = readSignals();
    const { mode, profile, idleSeconds: idle } = activeProfile(root);
    const code = admissionDecision(
      profile,
      requested.name,
      signals.cores,
      signals.memoryTotalMiB,
      signals.memoryAvailableMiB,
      signals.cpuSomeAvg10BasisPoints,
      signals.protectedCpuSomeAvg10BasisPoints,
      leased.memoryMiB,
      leased.batchCpus,
      leased.nativeCpus,
      requested.cpus,
      requested.memoryMiB,
      runs.filter(lease => batchClass(lease.class)).length,
      runs.filter(lease => lease.class === 'exclusive').length,
      runs.filter(lease => lease.aggregateSlice !== leaseSlice(lease.class)).length,
      queuedAhead,
    );
    const result = {
      decision: code === 'RUN' ? (create ? 'RESERVED' : 'RUN') : 'DEFER',
      reason: code,
      profile,
      mode,
      idleSeconds: idle === null ? null : Math.round(idle),
      class: requested.name,
      requestedCpus: requested.cpus,
      requestedMemoryMiB: requested.memoryMiB,
      leasedCpuCeilings: leased.cpus,
      leasedBatchCpus: leased.batchCpus,
      aggregateCpuLimit: aggregateCpus(profile, signals.cores),
      queuedAhead,
      leasedNativeCpus: leased.nativeCpus,
      leasedMemoryMiB: leased.memoryMiB,
      protectedCpuSomeAvg10: signals.protectedCpuSomeAvg10BasisPoints / 100,
      cpuSomeAvg10: signals.cpuSomeAvg10BasisPoints / 100,
      memoryFullAvg10: signals.memoryFullAvg10BasisPoints / 100,
      memoryAvailableMiB: signals.memoryAvailableMiB,
      reclaimed,
    };
    if (code !== 'RUN' || !create) return result;
    if (ticket !== null) dequeue(root, ticket);
    const id = crypto.randomUUID();
    const lease = {
      schema: 'agent-capacity-lease/v1',
      id,
      kind: create.kind,
      class: requested.name,
      aggregateSlice: create.kind === 'run' ? leaseSlice(requested.name) : null,
      owner: create.owner,
      cpus: requested.cpus,
      memoryMiB: requested.memoryMiB,
      createdAt: now,
      expiresAt: create.timeoutSeconds === null ? null : now + create.timeoutSeconds * 1000
        + (create.kind === 'run' ? runLeaseGraceMilliseconds : 0),
      ...(create.kind === 'run' ? {
        wrapperPid: process.pid,
        wrapperStart: processStart(process.pid),
      } : {}),
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

function changeLease(root, id, owner, timeoutSeconds, settledRun = false) {
  return withLock(root, () => {
    const path = exactLease(root, id);
    if (!existsSync(path)) fail(`unknown or expired lease: ${id}`, 75);
    const lease = JSON.parse(readFileSync(path, 'utf8'));
    if (lease.owner !== owner) fail(`lease owner mismatch: ${id}`);
    if (lease.kind === 'run' && !settledRun) fail('run leases belong to their foreground wrapper');
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

// Batch work is held in arrival order until admitted, never refused; native
// clients keep their immediate DEFER answer.
async function admit(root, requested, create) {
  if (!batchClass(requested.name)) return decision(root, requested, create);
  const ticket = enqueue(root);
  const leave = signal => () => {
    dequeue(root, ticket);
    process.exit(128 + ({ SIGHUP: 1, SIGINT: 2, SIGTERM: 15 })[signal]);
  };
  const handlers = ['SIGINT', 'SIGTERM', 'SIGHUP'].map(signal => [signal, leave(signal)]);
  for (const [signal, handler] of handlers) process.on(signal, handler);
  try {
    let reported = null;
    for (;;) {
      const result = decision(root, requested, create, ticket);
      if (result.decision === 'RESERVED') return result;
      if (result.reason !== reported) {
        print({ ...result, decision: 'QUEUED' }, process.stderr);
        reported = result.reason;
      }
      await Bun.sleep(queuePollMilliseconds + Math.random() * queuePollMilliseconds);
    }
  } finally {
    dequeue(root, ticket);
    for (const [signal, handler] of handlers) process.removeListener(signal, handler);
  }
}

async function runScoped(root, requested, owner, timeoutSeconds, command) {
  if (requested.name === 'agent') fail('run --class must be moderate, heavy, or exclusive');
  // The parent limit and weights must exist before any admitted command executes.
  if (!applyProfile(activeProfile(root).profile, readSignals().cores)) {
    fail('cannot establish aggregate CPU limit and native weight', 75);
  }
  const native = requested.name === 'native';
  const admitted = await admit(root, requested, { kind: 'run', owner, timeoutSeconds });
  print(admitted, process.stderr);
  if (admitted.decision !== 'RESERVED') return 75;
  const unit = scopeUnit(admitted.lease);
  const stop = () => {
    Bun.spawnSync(['systemctl', '--user', 'stop', unit], {
      stdin: 'ignore', stdout: 'ignore', stderr: 'ignore',
    });
  };
  try {
    const child = Bun.spawn([
      'systemd-run', '--user', '--scope', '--quiet', '--collect', '--expand-environment=no',
      `--unit=${unit}`,
      `--slice=${leaseSlice(requested.name)}`,
      // A quota-throttled game client stalls for the rest of each period.
      ...(native ? [] : [`--property=CPUQuota=${requested.cpus * 100}%`]),
      `--property=MemoryHigh=${requested.memoryMiB}M`,
      `--property=RuntimeMaxSec=${timeoutSeconds === null ? 'infinity' : `${timeoutSeconds}s`}`,
      '--property=KillMode=control-group',
      '--', ...command,
    ], { stdin: 'inherit', stdout: 'inherit', stderr: 'inherit' });
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
    process.once('SIGHUP', stop);
    return await child.exited;
  } finally {
    stop();
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
    process.removeListener('SIGHUP', stop);
    try {
      if (scopeLive(admitted.lease)) throw new Error(`scope still live; retained lease ${admitted.lease}`);
      print(changeLease(root, admitted.lease, owner, null, true), process.stderr);
    } catch (error) {
      process.stderr.write(`machine-capacity: lease cleanup failed: ${error?.message ?? String(error)}\n`);
    }
  }
}

async function main(argv) {
  const operation = argv[0];
  if (operation === 'fixture') {
    const parsed = parseKeyValues(argv, 1, new Set([
      '--profile', '--class', '--cores', '--memory-total-mib', '--memory-available-mib',
      '--protected-cpu-some-avg10-basis-points', '--memory-full-avg10-basis-points',
      '--leased-cpus', '--leased-native-cpus', '--leased-memory-mib',
      '--peer-batch-runs', '--peer-exclusive-runs', '--unbounded-runs',
      '--memory-gib', '--cpu-some-avg10-basis-points', '--queued-ahead',
    ]));
    if (parsed.separator !== argv.length) fail('fixture accepts no command');
    const cores = parsePositiveInteger(required(parsed.values, '--cores'), '--cores');
    const requested = parseClass(parsed.values, cores);
    const memoryFullAvg10 = parseNonnegativeInteger(
      required(parsed.values, '--memory-full-avg10-basis-points'), '--memory-full-avg10-basis-points',
    ) / 100;
    const leasedCpuCeilings = parseNonnegativeInteger(
      required(parsed.values, '--leased-cpus'), '--leased-cpus',
    );
    const profile = required(parsed.values, '--profile');
    if (profile !== 'attended' && profile !== 'unattended') fail('--profile must be attended or unattended');
    const code = admissionDecision(
      profile,
      requested.name,
      cores,
      parsePositiveInteger(required(parsed.values, '--memory-total-mib'), '--memory-total-mib'),
      parsePositiveInteger(required(parsed.values, '--memory-available-mib'), '--memory-available-mib'),
      parseNonnegativeInteger(parsed.values.get('--cpu-some-avg10-basis-points') ?? '0', '--cpu-some-avg10-basis-points'),
      parseNonnegativeInteger(required(parsed.values, '--protected-cpu-some-avg10-basis-points'), '--protected-cpu-some-avg10-basis-points'),
      parseNonnegativeInteger(required(parsed.values, '--leased-memory-mib'), '--leased-memory-mib'),
      leasedCpuCeilings,
      parseNonnegativeInteger(parsed.values.get('--leased-native-cpus') ?? '0', '--leased-native-cpus'),
      requested.cpus,
      requested.memoryMiB,
      parseNonnegativeInteger(parsed.values.get('--peer-batch-runs') ?? '0', '--peer-batch-runs'),
      parseNonnegativeInteger(parsed.values.get('--peer-exclusive-runs') ?? '0', '--peer-exclusive-runs'),
      parseNonnegativeInteger(parsed.values.get('--unbounded-runs') ?? '0', '--unbounded-runs'),
      parseNonnegativeInteger(parsed.values.get('--queued-ahead') ?? '0', '--queued-ahead'),
    );
    print({ decision: code, profile, class: requested.name, cpus: requested.cpus, memoryMiB: requested.memoryMiB, memoryFullAvg10,
      leasedCpuCeilings, aggregateCpuLimit: aggregateCpus(profile, cores) });
    return code === 'RUN' ? 0 : 75;
  }
  const root = runtimeRoot();
  if (operation === 'presence') {
    if (argv.length !== 1) fail('presence accepts no arguments');
    return watchPresence(root);
  }
  // Fixture runtimes exercise profiles from a recorded marker instead.
  if (process.env.XDG_RUNTIME_DIR === undefined || root.startsWith(`/run/user/${process.getuid()}/`)) {
    ensurePresenceWatcher();
  }
  if (operation === 'mode') {
    if (argv.length > 2) fail('usage: mode [away|present|auto]');
    if (argv.length === 2) {
      if (!modes.has(argv[1])) fail('mode must be away, present, or auto');
      ensureState(root);
      writeFileSync(join(root, 'mode'), `${argv[1]}\n`, { encoding: 'utf8', mode: 0o600 });
    }
    const active = activeProfile(root);
    if (!applyProfile(active.profile, readSignals().cores)) fail('cannot apply capacity profile', 75);
    print({ ...active, idleSeconds: active.idleSeconds === null ? null : Math.round(active.idleSeconds),
      aggregateCpuLimit: aggregateCpus(active.profile, readSignals().cores) });
    return 0;
  }
  if (operation === 'probe') {
    const { values, separator } = parseKeyValues(argv, 1, new Set(['--class', '--memory-gib']));
    if (separator !== argv.length) fail('probe accepts no command');
    const signals = readSignals();
    const result = decision(root, parseClass(values, signals.cores), null);
    print(result);
    return result.decision === 'RUN' ? 0 : 75;
  }
  if (operation === 'reserve') {
    const parsed = parseKeyValues(argv, 1, new Set(['--class', '--owner', '--timeout-seconds']));
    if (parsed.separator !== argv.length) fail('reserve accepts no command');
    if (!reserveClass(required(parsed.values, '--class'))) fail('reserve --class must be agent');
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
  if (operation === 'run' || operation === 'session') {
    const parsed = parseKeyValues(argv, 1, new Set(operation === 'session'
      ? ['--class', '--owner', '--memory-gib'] : ['--class', '--owner', '--timeout-seconds', '--memory-gib']));
    const command = argv.slice(parsed.separator + 1);
    if (parsed.separator === argv.length || command.length === 0) fail(`${operation} requires -- COMMAND ARG...`);
    const signals = readSignals();
    const requested = parseClass(parsed.values, signals.cores);
    return runScoped(
      root,
      requested,
      parseOwner(parsed.values),
      operation === 'session' ? null
        : parsePositiveInteger(required(parsed.values, '--timeout-seconds'), '--timeout-seconds', maximumTimeoutSeconds),
      command,
    );
  }
  fail('usage: probe|mode|reserve|renew|release|run|session; see machine-capacity');
}

process.exitCode = await main(Bun.argv.slice(2));
