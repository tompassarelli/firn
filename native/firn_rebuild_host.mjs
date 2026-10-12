// SPDX-License-Identifier: MIT OR Apache-2.0

import { appendFileSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const decoder = new TextDecoder();

globalThis.firn_host_get = (value, index) => value?.[index];
globalThis.firn_host_env = name => process.env[name] ?? null;
globalThis.firn_host_pid = () => process.pid;
globalThis.firn_host_out = text => process.stdout.write(text);
globalThis.firn_host_err = text => process.stderr.write(text);
globalThis.firn_host_capture = (argv, limit) => {
  try {
    const child = Bun.spawnSync({
      cmd: argv,
      env: process.env,
      stdin: 'ignore',
      stdout: 'pipe',
      stderr: 'pipe',
    });
    if (child.stdout.byteLength > limit || child.stderr.byteLength > limit) {
      return ['error', 27];
    }
    return [
      'ok',
      child.exitCode,
      decoder.decode(child.stdout),
      decoder.decode(child.stderr),
    ];
  } catch (error) {
    return ['error', Number(error?.errno ?? 5)];
  }
};
globalThis.firn_host_inherit = argv => {
  try {
    return Bun.spawnSync({
      cmd: argv,
      env: process.env,
      stdin: 'inherit',
      stdout: 'inherit',
      stderr: 'inherit',
    }).exitCode;
  } catch {
    return 126;
  }
};
globalThis.firn_host_git_checkout = path => existsSync(`${path}/.git`);
globalThis.firn_host_append = (path, text) => {
  try {
    appendFileSync(path, text, { encoding: 'utf8' });
    return ['ok'];
  } catch (error) {
    return ['error', Number(error?.errno ?? 5)];
  }
};

const modulePath = process.env.FIRN_REBUILD_MODULE
  ?? new URL('../lib/firn-rebuild/firn/rebuild-family.js', import.meta.url).pathname;
const args = Bun.argv.slice(2);
const coreTools = ['agents', 'threads', 'safe-push', 'worker-sweep', 'capacity-watchdog', 'codex-lead'];

const systemGeneration = () => {
  const link = Bun.spawnSync({ cmd: ['readlink', '/nix/var/nix/profiles/system'], stdin: 'ignore', stderr: 'ignore' });
  return /^system-(\d+)-link$/.exec(decoder.decode(link.stdout).trim())?.[1] ?? null;
};

const missingCoreTools = () => {
  const script = `for t in ${coreTools.join(' ')}; do command -v "$t" >/dev/null || echo "$t"; done`;
  const check = Bun.spawnSync({ cmd: [process.env.FIRN_TOOL_CHECK_SHELL ?? 'bash', '-lc', script], env: process.env, stdin: 'ignore', stderr: 'inherit' });
  const missing = decoder.decode(check.stdout).split(/\s+/).filter(Boolean);
  return missing.length > 0 || check.exitCode === 0 ? missing : ['(login shell check failed)'];
};

function review(previous, approved) {
  const root = process.env.FIRN_REPO ?? `${process.env.HOME}/code/nixos-config/main`;
  const git = words => Bun.spawnSync({ cmd: ['git', '-C', root, ...words], stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' });
  const base = previous === null ? null : git(['rev-parse', '--verify', `gen-${previous}^{commit}`]);
  if (!base || base.exitCode !== 0) {
    process.stderr.write('firn rebuild: last switched revision is unavailable; review cannot approve\n');
    return 65;
  }
  const revision = git(['rev-parse', 'HEAD']);
  if (revision.exitCode !== 0) return revision.exitCode;
  const start = decoder.decode(base.stdout).trim();
  const end = decoder.decode(revision.stdout).trim();
  const changes = git(['rev-list', '--first-parent', '--reverse', `${start}..${end}`, '--', 'config/galileo-revision']);
  if (changes.exitCode !== 0) return changes.exitCode;
  const ends = [];
  for (const change of decoder.decode(changes.stdout).trim().split('\n').filter(Boolean)) {
    const parent = git(['rev-parse', `${change}^`]);
    if (parent.exitCode !== 0) return parent.exitCode;
    ends.push(decoder.decode(parent.stdout).trim());
  }
  ends.push(end);
  const versions = join(process.env.FIRN_RUNTIME_ROOT ?? `${process.env.HOME}/.local/lib/firn/cli`, 'versions');
  const directory = mkdtempSync(join(tmpdir(), 'firn-review-'));
  const snapshot = join(directory, 'snapshot');
  try {
    const added = git(['worktree', 'add', '--detach', snapshot, end]);
    if (added.exitCode !== 0) {
      process.stderr.write(added.stderr);
      return added.exitCode;
    }
    let segmentStart = start;
    for (const segmentEnd of ends) {
      const checkout = Bun.spawnSync({ cmd: ['git', '-C', snapshot, 'checkout', '--detach', segmentEnd], stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' });
      if (checkout.exitCode !== 0) {
        process.stderr.write(checkout.stderr);
        return checkout.exitCode;
      }
      const pinFile = join(snapshot, 'config/galileo-revision');
      if (!existsSync(pinFile)) {
        process.stderr.write(`firn rebuild: ${segmentEnd} has no config/galileo-revision; review cannot approve\n`);
        return 2;
      }
      const pin = readFileSync(pinFile, 'utf8').trim();
      const cachedVersion = () => (existsSync(versions) ? readdirSync(versions) : []).find(name => {
        const cachedPin = join(versions, name, 'galileo-revision');
        return existsSync(cachedPin) && readFileSync(cachedPin, 'utf8').trim() === pin
          && existsSync(join(versions, name, 'bin/galileo'));
      });
      let version = cachedVersion();
      if (version === undefined) {
        const built = Bun.spawnSync({ cmd: ['bash', join(root, 'dotfiles/bin/firn-runtime-update'), 'galileo'], env: { ...process.env, FIRN_REPO: snapshot }, stdin: 'ignore', stdout: 'inherit', stderr: 'inherit' });
        if (built.exitCode !== 0) return built.exitCode;
        version = cachedVersion();
        if (version === undefined) {
          process.stderr.write(`firn rebuild: no cached Galileo binary for pin ${pin}; review cannot approve\n`);
          return 2;
        }
      }
      const galileo = join(versions, version, 'bin/galileo');
      process.stdout.write(`reviewing ${segmentStart}..${segmentEnd} with galileo ${pin}\n`);
      const status = Bun.spawnSync({ cmd: [galileo, 'review', '--base', segmentStart], cwd: snapshot, env: process.env, stdin: 'ignore', stdout: 'inherit', stderr: 'inherit' }).exitCode;
      if (status !== 0) return status;
      segmentStart = segmentEnd;
    }
    const originalRoot = process.env.FIRN_REPO;
    process.env.FIRN_REPO = snapshot;
    try {
      return approved();
    } finally {
      if (originalRoot === undefined) delete process.env.FIRN_REPO;
      else process.env.FIRN_REPO = originalRoot;
    }
  } finally {
    if (existsSync(snapshot)) {
      const removed = git(['worktree', 'remove', '--force', snapshot]);
      if (removed.exitCode !== 0) throw new Error(decoder.decode(removed.stderr));
    }
    rmdirSync(directory);
  }
}

if (args[0] === 'host' && args[1] === 'rebuild') {
  const previous = systemGeneration();
  const dryRun = args.includes('--dry-run');
  const rebuildArgs = args.filter(arg => arg !== '--dry-run');
  if (rebuildArgs.length > 3 || rebuildArgs.slice(2).some(arg => arg.startsWith('-'))) {
    process.stderr.write('Usage: firn rebuild [host] [--dry-run]\n');
    process.exitCode = 64;
  } else {
    const { run } = dryRun ? {} : await import(modulePath);
    const status = review(previous, () => dryRun ? 0 : run(rebuildArgs));
    const switched = !dryRun && (status === 0 || systemGeneration() !== previous);
    const missing = switched ? missingCoreTools() : [];
    if (missing.length === 0) {
      if (switched) process.stdout.write(`firn rebuild: core tools resolve in a login shell: ${coreTools.join(' ')}\n`);
      process.exitCode = status;
    } else {
      process.stderr.write(`\nfirn rebuild: !!! CORE TOOLS MISSING FROM A LOGIN SHELL'S PATH AFTER THE SWITCH: ${missing.join(' ')} !!!\n`);
      if (previous === null) {
        process.stderr.write('firn rebuild: previous system generation unknown; not rolling back\n');
      } else {
        process.stderr.write(`firn rebuild: switching back to system generation ${previous}\n`);
        run(['host', 'rollback', previous]);
      }
      process.exitCode = 70;
    }
  }
} else {
  const { run } = await import(modulePath);
  process.exitCode = run(args);
}
