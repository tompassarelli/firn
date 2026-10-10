import {
  appendFileSync,
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

import {
  admissionDecision,
  resourceClass,
  nativeMemoryRequest,
  reserveClass,
  aggregateCpus,
  batchClass,
  maximumSeconds,
  sessionSeconds,
  sizedClass,
  sizedResources,
  sizingHeadroom,
  chargedResources,
} from './machine-capacity-logic.ts';
const aggregateSlice = 'agent-capacity.slice';
// Sibling of session.slice (300), app.slice (100) and agent.slice (20): game
// clients outrank terminals and batch work but never the compositor.
const nativeSlice = 'native.slice';
const nativeCpuWeight = 200;
const gpuSampleMilliseconds = 500;
const nativeGpuSamples = 10;
const classNames = new Set(['agent', 'native', 'moderate', 'heavy', 'exclusive', 'gpu', 'critical']);
const nativeWaitingMilliseconds = 60000;
const modes = new Map([['present', 'attended'], ['away', 'unattended'], ['auto', null]]);
const idleSecondsForUnattended = 600;
const presenceUnit = 'agent-capacity-presence.service';
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
  if (!classNames.has(name)) fail('--class must be agent, native, moderate, heavy, exclusive, gpu, or critical');
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

// Tests point this at fixture slices to check which slices count as pressure.
const cgroupRoot = process.env.AGENT_CAPACITY_CGROUP_ROOT ?? '/sys/fs/cgroup';

function userManagerCgroup() {
  return `${cgroupRoot}/user.slice/user-${process.getuid()}.slice/user@${process.getuid()}.service`;
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
    // Oversubscription is read where non-lease work waits: /proc/pressure/cpu also
    // counts a lease scope stalled by its own CPUQuota, which held the queue on an
    // idle machine (9 Oct: one 2-CPU lease read as 37% system pressure).
    cpuSomeAvg10BasisPoints: process.env.AGENT_CAPACITY_CPU_PRESSURE
      ? parsePsi(process.env.AGENT_CAPACITY_CPU_PRESSURE, 'some')
      : Math.max(
        parsePsi(join(cgroupRoot, 'system.slice', 'cpu.pressure'), 'some'),
        slicePressure('app.slice'), slicePressure('background.slice'),
        slicePressure('session.slice'), slicePressure(nativeSlice)),
    protectedCpuSomeAvg10BasisPoints: Math.max(slicePressure('session.slice'), slicePressure(nativeSlice)),
    memoryFullAvg10BasisPoints: parsePsi('/proc/pressure/memory', 'full'),
  };
}

function gpuBusyPath() {
  if (process.env.AGENT_CAPACITY_GPU_BUSY) return process.env.AGENT_CAPACITY_GPU_BUSY;
  const card = readdirSync('/sys/class/drm').find(name => /^card[0-9]+$/.test(name)
    && existsSync(`/sys/class/drm/${name}/device/gpu_busy_percent`));
  return card === undefined ? null : `/sys/class/drm/${card}/device/gpu_busy_percent`;
}

function readGpu(samples) {
  const path = gpuBusyPath();
  let total = 0;
  for (let index = 0; path !== null && index < samples; index += 1) {
    if (index > 0) Bun.sleepSync(gpuSampleMilliseconds);
    total += Number(readFileSync(path, 'utf8').trim()) || 0;
  }
  let clients = 0;
  if (process.env.AGENT_CAPACITY_GPU_CLIENTS !== undefined) clients = Number(process.env.AGENT_CAPACITY_GPU_CLIENTS);
  else for (const pid of readdirSync('/proc')) {
    if (!/^[0-9]+$/.test(pid)) continue;
    try {
      if (readFileSync(`/proc/${pid}/comm`, 'utf8').startsWith('Warcraft III')) clients += 1;
    } catch (error) {
      if (error?.code !== 'ENOENT' && error?.code !== 'ESRCH') throw error;
    }
  }
  return { gpuBusyPercent: path === null ? 0 : Math.round(total / samples), gpuClients: clients };
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
  sampleUnleased(root);
  setInterval(() => sampleUnleased(root), unleasedSampleMilliseconds);
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

function stateRoot() {
  return process.env.XDG_STATE_HOME ?? join(process.env.HOME ?? '/tmp', '.local', 'state');
}

function usageLogPath() {
  return process.env.AGENT_CAPACITY_USAGE_LOG ?? join(stateRoot(), 'agents', 'machine-capacity-usage.jsonl');
}

function readText(path) {
  try {
    return readFileSync(path, 'utf8');
  } catch (error) {
    if (['ENOENT', 'ESRCH', 'ENODEV', 'EACCES', 'ENOTDIR'].includes(error?.code)) return null;
    throw error;
  }
}

function cgroupUsageUsec(path) {
  const match = readText(join(path, 'cpu.stat'))?.match(/^usage_usec ([0-9]+)$/m);
  return match ? Number(match[1]) : null;
}

const shellCommands = new Set(['bash', 'sh', 'zsh', 'dash']);
const shellBuiltins = new Set(['cd', 'wait', 'echo', 'printf', 'export', 'set', 'true', 'exit', 'source', '.']);
const wrapperCommands = new Set(['exec', 'env', 'nice', 'ionice', 'timeout', 'time', 'nohup', 'stdbuf']);

// A stable key for "the same kind of work": the program and its subcommand words.
function commandShape(command) {
  let words = [...command];
  let unwrappedShell = false;
  for (let guard = 0; guard < 8 && words.length > 0; guard += 1) {
    const program = words[0].split('/').at(-1);
    if (!unwrappedShell && shellCommands.has(program) && words[1] === '-c' && words[2] !== undefined) {
      unwrappedShell = true;
      words = words[2].split(/[;&|\n]+/).map(part => part.trim().split(/\s+/))
        .find(part => part[0] !== '' && !shellBuiltins.has(part[0])) ?? [];
    } else if (wrapperCommands.has(program) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0])) {
      words = words.slice(1);
      while (words.length > 0 && (words[0].startsWith('-') || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0]) || /^[0-9.]+[smhd]?$/.test(words[0]))) {
        words = words.slice(1);
      }
    } else break;
  }
  if (words.length === 0) return 'unknown';
  const shape = [words[0].split('/').at(-1)];
  for (const word of words.slice(1)) {
    if (shape.length >= 3 || !/^[a-z][a-z0-9:_-]*$/.test(word)) break;
    shape.push(word);
  }
  return shape.join(' ');
}

// Per-process GPU engine time from amdgpu fdinfo, summed once per DRM client.
function gpuEngineNanoseconds(pids, perClient) {
  for (const pid of pids) {
    let fds;
    try {
      fds = readdirSync(`/proc/${pid}/fdinfo`);
    } catch {
      continue;
    }
    for (const fd of fds) {
      const text = readText(`/proc/${pid}/fdinfo/${fd}`);
      if (text === null || !text.includes('drm-driver:\tamdgpu')) continue;
      const client = text.match(/^drm-client-id:\s+([0-9]+)$/m)?.[1];
      if (client === undefined) continue;
      let total = 0;
      for (const match of text.matchAll(/^drm-engine-[a-z_]+:\s+([0-9]+) ns$/gm)) total += Number(match[1]);
      perClient.set(client, Math.max(perClient.get(client) ?? 0, total));
    }
  }
}

function scopeCgroup(className, unit) {
  return className === 'native'
    ? join(userManagerCgroup(), nativeSlice, unit)
    : join(userManagerCgroup(), 'agent.slice', aggregateSlice, unit);
}

const usageSampleMilliseconds = 1000;
const peakWindowMilliseconds = 5000;
const gpuEverySamples = 5;

// Samples the lease scope while it runs; the scope's cgroup disappears with its last process.
function measureScope(root, lease, cgroup) {
  const startedAt = Date.now();
  const samples = [];
  const perClient = new Map();
  const recent = [];
  const usage = { cpuSeconds: 0, meanCores: 0, peakCores: 0, recentCores: 0, peakMemoryMiB: 0, memoryMiB: 0, gpuSeconds: 0 };
  let count = 0;
  const sample = () => {
    const now = Date.now();
    const usec = cgroupUsageUsec(cgroup);
    if (usec === null) return;
    samples.push([now, usec]);
    while (samples.length > 2 && now - samples[1][0] >= peakWindowMilliseconds) samples.shift();
    const [then, before] = samples[0];
    if (now - then >= peakWindowMilliseconds / 2) {
      usage.recentCores = (usec - before) / 1000 / (now - then);
      usage.peakCores = Math.max(usage.peakCores, usage.recentCores);
      recent.push(usage.recentCores);
    }
    usage.cpuSeconds = usec / 1e6;
    usage.meanCores = usage.cpuSeconds / Math.max((now - startedAt) / 1000, 1);
    const peak = Number(readText(join(cgroup, 'memory.peak'))?.trim());
    const current = Number(readText(join(cgroup, 'memory.current'))?.trim());
    if (Number.isFinite(peak)) usage.peakMemoryMiB = Math.max(usage.peakMemoryMiB, peak / 1048576);
    if (Number.isFinite(current)) usage.memoryMiB = current / 1048576;
    if (count % gpuEverySamples === 0) {
      const pids = (readText(join(cgroup, 'cgroup.procs')) ?? '').split('\n').filter(Boolean);
      gpuEngineNanoseconds(pids, perClient);
      usage.gpuSeconds = [...perClient.values()].reduce((sum, value) => sum + value, 0) / 1e9;
    }
    count += 1;
    try {
      writeFileSync(join(root, 'leases', `${lease}.usage`), `${JSON.stringify({ ...usage, at: now })}\n`, { mode: 0o600 });
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
  };
  const timer = setInterval(sample, usageSampleMilliseconds);
  return {
    sample,
    finish() {
      clearInterval(timer);
      sample();
      return { ...usage, p90Cores: recent.length > 0 ? percentile(recent, 0.9) : null, wallSeconds: (Date.now() - startedAt) / 1000 };
    },
  };
}

const round = (value, digits = 2) => Math.round(value * 10 ** digits) / 10 ** digits;

function recordUsage(entry) {
  const path = usageLogPath();
  mkdirSync(join(path, '..'), { recursive: true, mode: 0o700 });
  appendFileSync(path, `${JSON.stringify(entry)}\n`, { mode: 0o600 });
}

const sizingRuns = 20;
const sizingMinimumRuns = 3;

function percentile(values, share) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(share * sorted.length) - 1)];
}

// The class and size measured runs of this command shape need; moderate until three runs exist.
function sizeFromUsage(command, cores) {
  const shape = commandShape(command);
  const runs = (readText(usageLogPath()) ?? '').split('\n').slice(-2000).flatMap(line => {
    try {
      const entry = JSON.parse(line);
      return entry.shape === shape && entry.wallSeconds > 0 ? [entry] : [];
    } catch {
      return [];
    }
  }).slice(-sizingRuns);
  if (runs.length < sizingMinimumRuns) {
    return { name: 'moderate', ...resourceClass('moderate', cores), sizing: { shape, runs: runs.length, basis: 'default' } };
  }
  const cpus = Math.ceil(percentile(runs.map(entry => entry.peakCores), 0.9) * sizingHeadroom());
  const memory = Math.ceil(percentile(runs.map(entry => entry.peakMemoryMiB), 0.9) * sizingHeadroom() / 256) * 256;
  const gpuShare = percentile(runs.map(entry => (entry.gpuSeconds ?? 0) / entry.wallSeconds), 0.5);
  const resources = sizedResources(cpus, memory, cores);
  return {
    name: sizedClass(gpuShare, resources.cpus, resources.memoryMiB), ...resources,
    sizing: { shape, runs: runs.length, basis: 'p90', gpuShare: round(gpuShare) },
  };
}

const ownerPrefix = owner => owner.match(/^[A-Za-z]*/)[0];

// Admission charges a declared class what this owner prefix's runs of the command measured.
function chargeFromUsage(requested, owner, command, cores) {
  const shape = commandShape(command);
  const prefix = ownerPrefix(owner);
  const runs = (readText(usageLogPath()) ?? '').split('\n').slice(-5000).flatMap(line => {
    try {
      const entry = JSON.parse(line);
      return entry.class === requested.name && entry.shape === shape && typeof entry.owner === 'string'
        && ownerPrefix(entry.owner) === prefix && entry.wallSeconds > 0 ? [entry] : [];
    } catch {
      return [];
    }
  }).slice(-sizingRuns);
  const charged = chargedResources(requested.name, cores,
    runs.map(entry => entry.p90Cores ?? entry.peakCores), runs.map(entry => entry.peakMemoryMiB));
  return {
    ...requested, cpus: round(charged.cpus), memoryMiB: Math.ceil(charged.memoryMiB),
    declared: { cpus: requested.cpus, memoryMiB: requested.memoryMiB }, evidence: { key: `${prefix} ${shape}`, runs: runs.length },
  };
}

function readUsage(root, id) {
  try {
    return JSON.parse(readFileSync(join(root, 'leases', `${id}.usage`), 'utf8'));
  } catch {
    return null;
  }
}

const unleasedWindowMilliseconds = 120000;
const unleasedSampleMilliseconds = 30000;
const unleasedCoreThreshold = 1;

// Leaf cgroups outside lease scopes, the desktop session and native clients.
function unleasedCgroups() {
  const manager = userManagerCgroup();
  const skip = new Set([
    join(manager, 'session.slice'), join(manager, nativeSlice), join(manager, 'init.scope'),
    join(manager, 'agent.slice', aggregateSlice),
  ]);
  const leaves = [];
  const walk = (path, depth) => {
    if (skip.has(path)) return;
    let children = [];
    try {
      children = readdirSync(path, { withFileTypes: true }).filter(entry => entry.isDirectory());
    } catch {
      return;
    }
    if ((readText(join(path, 'cgroup.procs')) ?? '').trim() !== '' || children.length === 0) leaves.push(path);
    if (depth < 6) for (const child of children) walk(join(path, child.name), depth + 1);
  };
  walk(manager, 0);
  walk(join(cgroupRoot, 'system.slice'), 0);
  return leaves;
}

function processTicks(pid) {
  const stat = readText(`/proc/${pid}/stat`);
  if (stat === null) return null;
  const fields = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
  return { ticks: Number(fields[11]) + Number(fields[12]), start: fields[19] };
}

function takeUnleasedSample(now) {
  const cgroups = {};
  const pids = {};
  for (const path of unleasedCgroups()) {
    const usec = cgroupUsageUsec(path);
    if (usec === null) continue;
    cgroups[path] = usec;
    for (const pid of (readText(join(path, 'cgroup.procs')) ?? '').split('\n').filter(Boolean)) {
      const ticks = processTicks(pid);
      if (ticks !== null) pids[pid] = { ...ticks, cgroup: path };
    }
  }
  return { at: now, cgroups, pids };
}

// Cgroups whose CPU use averaged more than one core across the window.
function unleasedHeavy(older, newer) {
  const seconds = (newer.at - older.at) / 1000;
  const manager = userManagerCgroup();
  const heavy = [];
  for (const [path, usec] of Object.entries(newer.cgroups)) {
    if (older.cgroups[path] === undefined) continue;
    const cores = (usec - older.cgroups[path]) / 1e6 / seconds;
    if (cores <= unleasedCoreThreshold) continue;
    const top = Object.entries(newer.pids)
      .filter(([pid, entry]) => entry.cgroup === path && older.pids[pid]?.start === entry.start)
      .map(([pid, entry]) => ({ pid: Number(pid), cores: (entry.ticks - older.pids[pid].ticks) / 100 / seconds }))
      .filter(entry => entry.cores >= 0.25)
      .sort((left, right) => right.cores - left.cores).slice(0, 3)
      .map(entry => ({
        ...entry, cores: round(entry.cores),
        command: (readText(`/proc/${entry.pid}/cmdline`) ?? '').replaceAll('\0', ' ').trim().slice(0, 120),
      }));
    heavy.push({ cgroup: path.startsWith(manager) ? path.slice(manager.length + 1) : path.slice(cgroupRoot.length + 1), cores: round(cores), top });
  }
  return heavy.sort((left, right) => right.cores - left.cores);
}

function sampleUnleased(root, now = Number(process.env.AGENT_CAPACITY_NOW ?? Date.now())) {
  ensureState(root);
  const path = join(root, 'unleased-samples.json');
  let samples = [];
  try {
    samples = JSON.parse(readFileSync(path, 'utf8'));
  } catch {}
  samples = [...samples.filter(sample => now - sample.at <= unleasedWindowMilliseconds * 2), takeUnleasedSample(now)];
  writeFileSync(path, JSON.stringify(samples), { mode: 0o600 });
  const older = samples.filter(sample => now - sample.at >= unleasedWindowMilliseconds).at(-1);
  const result = older === undefined ? null : {
    at: now, windowSeconds: Math.round((now - older.at) / 1000), heavy: unleasedHeavy(older, samples.at(-1)),
  };
  if (result !== null) writeFileSync(join(root, 'unleased.json'), `${JSON.stringify(result)}\n`, { mode: 0o600 });
  return result;
}

// Null when the presence watcher has not yet covered a full window.
function readUnleased(root) {
  try {
    const result = JSON.parse(readFileSync(join(root, 'unleased.json'), 'utf8'));
    const now = Number(process.env.AGENT_CAPACITY_NOW ?? Date.now());
    if (now - result.at > unleasedSampleMilliseconds * 3) return null;
    return { heavy: result.heavy, cores: round(result.heavy.reduce((sum, entry) => sum + entry.cores, 0)), windowSeconds: result.windowSeconds };
  } catch {
    return null;
  }
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
      rmSync(path.replace(/\.json$/, '.usage'), { force: true });
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
function enqueue(root, className, owner) {
  ensureState(root);
  const name = `${String(Date.now()).padStart(15, '0')}-${crypto.randomUUID()}.json`;
  writeFileSync(join(root, 'queue', name), `${JSON.stringify({
    wrapperPid: process.pid, wrapperStart: processStart(process.pid), class: className, owner,
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
    waiting.push({ ...ticket, name, queuedAt: Number(name.slice(0, 15)) });
  }
  return waiting;
}

// Admission order: critical, then exclusive, then the rest, each part in arrival order.
function priorityOrder(queue) {
  const rank = ticket => ticket.class === 'critical' ? 0 : ticket.class === 'exclusive' ? 1 : 2;
  return [0, 1, 2].flatMap(level => queue.filter(ticket => rank(ticket) === level));
}

function leaseSlice(className) {
  return className === 'native' ? nativeSlice : aggregateSlice;
}

function nativeWaiting(root, now) {
  try {
    return now - statSync(join(root, 'native-waiting')).mtimeMs < nativeWaitingMilliseconds ? 1 : 0;
  } catch (error) {
    if (error?.code === 'ENOENT') return 0;
    throw error;
  }
}

function markNativeWaiting(root, waiting) {
  if (waiting) writeFileSync(join(root, 'native-waiting'), '', { mode: 0o600 });
  else rmSync(join(root, 'native-waiting'), { force: true });
}

function decision(root, requested, create, ticket = null) {
  const gpu = readGpu(requested.name === 'native' && !process.env.AGENT_CAPACITY_GPU_BUSY ? nativeGpuSamples : 1);
  return withLock(root, () => {
    const now = Date.now();
    const { active, reclaimed } = readLeases(root, now);
    const queue = readQueue(root);
    // Gpu tickets wait for render slots in their own line, so they hold no CPU work.
    const queuedAhead = queue.filter(entry => (ticket === null || entry.name < ticket)
      && (entry.class === 'gpu') === (requested.name === 'gpu')
      && (!['moderate', 'gpu'].includes(requested.name) || entry.class !== 'exclusive')).length;
    const exclusiveWaiting = queue.filter(entry => entry.class === 'exclusive'
      && (requested.name !== 'exclusive' || ticket === null || entry.name < ticket)).length;
    const leased = totals(active);
    const runs = active.filter(lease => lease.kind === 'run');
    const unleased = readUnleased(root);
    const committedBatchCpus = round(runs.filter(lease => batchClass(lease.class))
      .reduce((sum, lease) => sum + Math.max(lease.cpus, readUsage(root, lease.id)?.recentCores ?? 0), 0)
      + (unleased?.cores ?? 0));
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
      exclusiveWaiting,
      gpu.gpuBusyPercent,
      gpu.gpuClients,
      runs.filter(lease => lease.class === 'gpu').length,
      nativeWaiting(root, now),
    );
    if (requested.name === 'native') markNativeWaiting(root, code !== 'RUN');
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
      ...(requested.sizing ? { sizing: requested.sizing } : {}),
      ...(requested.declared ? { declaredCpus: requested.declared.cpus, declaredMemoryMiB: requested.declared.memoryMiB, evidence: requested.evidence } : {}),
      aggregateCpuLimit: aggregateCpus(profile, signals.cores),
      queuedAhead,
      exclusiveWaiting,
      leasedNativeCpus: leased.nativeCpus,
      leasedMemoryMiB: leased.memoryMiB,
      protectedCpuSomeAvg10: signals.protectedCpuSomeAvg10BasisPoints / 100,
      cpuSomeAvg10: signals.cpuSomeAvg10BasisPoints / 100,
      memoryFullAvg10: signals.memoryFullAvg10BasisPoints / 100,
      memoryAvailableMiB: signals.memoryAvailableMiB,
      ...gpu,
      gpuLeases: runs.filter(lease => lease.class === 'gpu').length,
      unleasedHeavyCores: unleased?.cores ?? null,
      committedBatchCpus,
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
      ...(requested.declared ? { declared: requested.declared, evidence: requested.evidence } : {}),
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
      rmSync(path.replace(/\.json$/, '.usage'), { force: true });
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

function measuredView(usage) {
  if (usage === null) return null;
  return {
    cores: round(usage.recentCores), peakCores: round(usage.peakCores), meanCores: round(usage.meanCores),
    memoryMiB: Math.round(usage.memoryMiB), peakMemoryMiB: Math.round(usage.peakMemoryMiB), gpuSeconds: round(usage.gpuSeconds),
  };
}

function status(root) {
  const gpu = readGpu(1);
  return withLock(root, () => {
    const now = Date.now();
    const { active, reclaimed } = readLeases(root, now);
    const { mode, profile } = activeProfile(root);
    const seconds = milliseconds => Math.round(milliseconds / 1000);
    return {
      profile,
      mode,
      ...gpu,
      holding: active.sort((left, right) => left.createdAt - right.createdAt).map(lease => ({
        owner: lease.owner,
        class: lease.class,
        kind: lease.kind,
        cpus: lease.cpus,
        memoryMiB: lease.memoryMiB,
        declaredCpus: lease.declared?.cpus ?? lease.cpus,
        declaredMemoryMiB: lease.declared?.memoryMiB ?? lease.memoryMiB,
        evidenceRuns: lease.evidence?.runs ?? 0,
        measured: lease.kind === 'run' ? measuredView(readUsage(root, lease.id)) : null,
        heldSeconds: seconds(now - lease.createdAt),
        remainingSeconds: lease.expiresAt === null ? null : seconds(lease.expiresAt - now),
      })),
      queued: priorityOrder(readQueue(root)).map((ticket, index) => ({
        position: index + 1,
        owner: ticket.owner ?? null,
        class: ticket.class ?? null,
        waitingSeconds: seconds(now - ticket.queuedAt),
      })),
      unleasedHeavy: readUnleased(root),
      reclaimed,
    };
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
  const ticket = enqueue(root, requested.name, create.owner);
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
  if (requested.name === 'agent') fail('run --class must be moderate, heavy, exclusive, gpu, critical, or native');
  // The parent limit and weights must exist before any admitted command executes.
  if (!applyProfile(activeProfile(root).profile, readSignals().cores)) {
    fail('cannot establish aggregate CPU limit and native weight', 75);
  }
  const native = requested.name === 'native';
  const limits = requested.declared ?? requested;
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
      ...(native ? [] : [`--property=CPUQuota=${limits.cpus * 100}%`]),
      `--property=MemoryHigh=${limits.memoryMiB}M`,
      `--property=RuntimeMaxSec=${timeoutSeconds === null ? 'infinity' : `${timeoutSeconds}s`}`,
      '--property=KillMode=control-group',
      '--', ...command,
    ], { stdin: 'inherit', stdout: 'inherit', stderr: 'inherit' });
    const measurement = measureScope(root, admitted.lease, scopeCgroup(requested.name, unit));
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
    process.once('SIGHUP', stop);
    const exitCode = await child.exited;
    const usage = measurement.finish();
    const rusage = child.resourceUsage();
    const cpuSeconds = Math.max(usage.cpuSeconds, Number(rusage?.cpuTime?.total ?? 0n) / 1e6);
    try {
      recordUsage({
        at: new Date().toISOString(), owner, shape: commandShape(command), class: requested.name,
        reservedCpus: limits.cpus, reservedMemoryMiB: limits.memoryMiB,
        chargedCpus: requested.cpus, chargedMemoryMiB: requested.memoryMiB, exitCode,
        wallSeconds: round(usage.wallSeconds), cpuSeconds: round(cpuSeconds),
        meanCores: round(cpuSeconds / Math.max(usage.wallSeconds, 0.001)),
        p90Cores: round(usage.p90Cores ?? cpuSeconds / Math.max(usage.wallSeconds, 0.001)),
        peakCores: round(Math.max(usage.peakCores, cpuSeconds / Math.max(usage.wallSeconds, 0.001))),
        peakMemoryMiB: Math.round(Math.max(usage.peakMemoryMiB, (rusage?.maxRSS ?? 0) / 1024)),
        gpuSeconds: round(usage.gpuSeconds),
      });
    } catch (error) {
      process.stderr.write(`machine-capacity: usage log failed: ${error?.message ?? String(error)}\n`);
    }
    return exitCode;
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
      '--memory-gib', '--cpu-some-avg10-basis-points', '--queued-ahead', '--exclusive-waiting',
      '--gpu-busy-percent', '--gpu-clients', '--gpu-runs', '--native-waiting',
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
      parseNonnegativeInteger(parsed.values.get('--exclusive-waiting') ?? '0', '--exclusive-waiting'),
      parseNonnegativeInteger(parsed.values.get('--gpu-busy-percent') ?? '0', '--gpu-busy-percent'),
      parseNonnegativeInteger(parsed.values.get('--gpu-clients') ?? '0', '--gpu-clients'),
      parseNonnegativeInteger(parsed.values.get('--gpu-runs') ?? '0', '--gpu-runs'),
      parseNonnegativeInteger(parsed.values.get('--native-waiting') ?? '0', '--native-waiting'),
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
  if (operation === 'sample-unleased') {
    print(sampleUnleased(root));
    return 0;
  }
  if (operation === 'status') {
    if (argv.length !== 1) fail('status accepts no arguments');
    print(status(root), process.stdout);
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
      required(parsed.values, '--timeout-seconds'), '--timeout-seconds', maximumSeconds('agent'),
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
      ? parsePositiveInteger(required(parsed.values, '--timeout-seconds'), '--timeout-seconds', maximumSeconds('agent'))
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
    const parsed = parseKeyValues(argv, 1, new Set(['--class', '--owner', '--timeout-seconds', '--memory-gib']));
    const command = argv.slice(parsed.separator + 1);
    if (parsed.separator === argv.length || command.length === 0) fail(`${operation} requires -- COMMAND ARG...`);
    const signals = readSignals();
    if (!parsed.values.has('--class') && operation === 'session') fail('session requires --class');
    const owner = parseOwner(parsed.values);
    const requested = parsed.values.has('--memory-gib') ? parseClass(parsed.values, signals.cores)
      : parsed.values.has('--class') ? chargeFromUsage(parseClass(parsed.values, signals.cores), owner, command, signals.cores)
        : sizeFromUsage(command, signals.cores);
    // A session without one takes its class's default deadline; native sessions have none.
    const timeoutSeconds = parsed.values.has('--timeout-seconds') || operation === 'run'
      ? parsePositiveInteger(required(parsed.values, '--timeout-seconds'), '--timeout-seconds',
        maximumSeconds(requested.name))
      : sessionSeconds(requested.name) || null;
    return runScoped(root, requested, owner, timeoutSeconds, command);
  }
  fail('usage: status|probe|mode|reserve|renew|release|run|session; see machine-capacity');
}

process.exitCode = await main(Bun.argv.slice(2));
