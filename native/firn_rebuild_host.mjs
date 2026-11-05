// SPDX-License-Identifier: MIT OR Apache-2.0

import { appendFileSync, existsSync, mkdtempSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { retireSnapshotsOnTermination } from './firn_snapshot_retire.mjs';

const decoder = new TextDecoder();

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
  ?? new URL('./firn_rebuild_family.ts', import.meta.url).pathname;
const args = Bun.argv.slice(2);
const firnRoot = process.env.FIRN_REPO ?? `${process.env.HOME}/code/nixos-config/main`;
const rebuildSnapshot = process.env.FIRN_SNAPSHOT_DIR || `${process.env.XDG_RUNTIME_DIR || '/tmp'}/firn-rebuild-snapshot-${process.pid}`;
let reviewSnapshot = null;
if (args[0] === 'host' && (args[1] === 'rebuild' || args[1] === 'prepare')) retireSnapshotsOnTermination(firnRoot, () => [rebuildSnapshot, reviewSnapshot].filter(Boolean));
const coreTools = ['agents', 'threads', 'safe-push'];

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

const gitIn = root => words => Bun.spawnSync({ cmd: ['git', '-C', root, ...words], stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' });

const hostName = () => process.env.FIRN_HOST
  ?? decoder.decode(Bun.spawnSync({ cmd: ['hostname'], stdin: 'ignore', stderr: 'ignore' }).stdout).trim();

const switchedRevision = () => {
  const profile = process.env.FIRN_SYSTEM_PROFILE ?? '/nix/var/nix/profiles/system';
  try {
    const shown = Bun.spawnSync({ cmd: [`${profile}/sw/bin/nixos-version`, '--configuration-revision'], stdin: 'ignore', stdout: 'pipe', stderr: 'ignore' });
    const revision = decoder.decode(shown.stdout).trim();
    return shown.exitCode === 0 && /^[0-9a-f]{40}$/.test(revision) ? revision : null;
  } catch {
    return null;
  }
};

function switchedBase(previous, root) {
  if (previous === null) return null;
  const git = gitIn(root);
  const tagged = git(['rev-parse', '--verify', '-q', `gen-${hostName()}-${previous}^{commit}`]);
  if (tagged.exitCode === 0) return { label: '', git, start: decoder.decode(tagged.stdout).trim() };
  const revision = switchedRevision();
  if (revision === null) return null;
  if (git(['cat-file', '-e', `${revision}^{commit}`]).exitCode === 0) return { label: '', git, start: revision };
  const systemRoot = process.env.FIRN_SYSTEM_FLAKE ?? `${process.env.HOME}/code/south/main`;
  const systemGit = gitIn(systemRoot);
  if (systemGit(['cat-file', '-e', `${revision}^{commit}`]).exitCode === 0) return { label: 'system flake ', git: systemGit, start: revision };
  return null;
}

const staleRefusal = root => {
  const git = gitIn(root);
  const fetched = Bun.spawnSync({
    cmd: ['git', '-C', root, 'fetch', '--quiet', 'origin', 'main'],
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
    stdin: 'ignore',
    stdout: 'ignore',
    stderr: 'ignore',
    timeout: 10000,
  });
  const origin = git(['rev-parse', '--verify', '-q', 'origin/main^{commit}']);
  if (origin.exitCode !== 0) return null;
  const tip = decoder.decode(origin.stdout).trim();
  const head = git(['rev-parse', 'HEAD']);
  if (head.exitCode !== 0 || decoder.decode(head.stdout).trim() === tip) return null;
  if (git(['merge-base', '--is-ancestor', 'HEAD', tip]).exitCode !== 0) return null;
  const source = fetched.exitCode === 0 ? 'origin/main' : 'the last fetched origin/main (fetch failed)';
  return `firn rebuild: this checkout is behind ${source} ${tip}; run: firn rebuild --landed ${tip}\n`;
};

function review(previous, approved) {
  const root = process.env.FIRN_REPO ?? `${process.env.HOME}/code/nixos-config/main`;
  const git = gitIn(root);
  const base = switchedBase(previous, root);
  if (base === null) {
    process.stderr.write('firn rebuild: last switched revision is unavailable; review cannot approve\n');
    return 65;
  }
  const revision = git(['rev-parse', 'HEAD']);
  if (revision.exitCode !== 0) return revision.exitCode;
  const reviewed = base.git(['rev-parse', 'HEAD']);
  if (reviewed.exitCode !== 0) return reviewed.exitCode;
  const { start } = base;
  const snapshotRevision = decoder.decode(revision.stdout).trim();
  const end = decoder.decode(reviewed.stdout).trim();
  const directory = mkdtempSync(join(tmpdir(), 'firn-review-'));
  const snapshot = join(directory, 'snapshot');
  reviewSnapshot = snapshot;
  try {
    const added = git(['worktree', 'add', '--detach', snapshot, snapshotRevision]);
    if (added.exitCode !== 0) {
      process.stderr.write(added.stderr);
      return added.exitCode;
    }
    process.stdout.write(`reviewing ${base.label}${start}..${end} with Nix evaluation\n`);
    const diff = base.git(['diff', '--stat', start, end]);
    if (diff.exitCode !== 0) return diff.exitCode;
    process.stdout.write(diff.stdout);
    const checked = Bun.spawnSync({ cmd: ['bash', join(root, 'dotfiles/bin/firn-check')], cwd: snapshot,
      env: { ...process.env, FIRN_REPO: snapshot }, stdin: 'ignore', stdout: 'inherit', stderr: 'inherit' });
    if (checked.exitCode !== 0) return checked.exitCode ?? 2;
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
    reviewSnapshot = null;
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
    const stale = staleRefusal(process.env.FIRN_REPO ?? `${process.env.HOME}/code/nixos-config/main`);
    if (stale !== null) {
      process.stderr.write(stale);
      process.exit(64);
    }
    const { run, foreignRebuild } = dryRun ? {} : await import(modulePath);
    const refusal = foreignRebuild?.(rebuildArgs) ?? null;
    if (refusal !== null) {
      process.stderr.write(refusal);
      process.exit(64);
    }
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
