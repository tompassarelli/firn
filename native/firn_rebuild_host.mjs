// SPDX-License-Identifier: MIT OR Apache-2.0

import { appendFileSync, existsSync } from 'node:fs';

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
const { run } = await import(modulePath);
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

if (args[0] === 'host' && args[1] === 'rebuild') {
  const previous = systemGeneration();
  const status = run(args);
  const switched = status === 0 || systemGeneration() !== previous;
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
} else {
  process.exitCode = run(args);
}
