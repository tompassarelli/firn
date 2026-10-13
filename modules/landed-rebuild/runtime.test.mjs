import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = mkdtempSync(join(tmpdir(), 'firn-landed-effects-'));
try {
  const firn = join(root, 'firn');
  const system = join(root, 'system');
  mkdirSync(`${firn}/.git`, { recursive: true });
  mkdirSync(`${system}/.git`, { recursive: true });
  Object.assign(process.env, {
    FIRN_REPO: firn, FIRN_SYSTEM_FLAKE: system, FIRN_SNAPSHOT_DIR: `${root}/validation`,
    FIRN_LANDED_USER: 'tom', FIRN_LANDED_HOME: '/home/tom', FIRN_LANDED_UID: '1000',
    FIRN_LANDED_ENVIRONMENT_SWITCH: '/nix/store/fixture-environment-switch',
  });
  const commands = [];
  const revision = 'a'.repeat(40);
  const closure = `/nix/store/${'b'.repeat(32)}-system`;
  const encoder = new TextEncoder();
  Bun.spawnSync = options => {
    const argv = options.cmd;
    commands.push(argv);
    let out = '';
    if (argv[0] === 'uname') out = 'Linux\n';
    if (argv[0] === 'git' && argv.includes('rev-parse')) out = `${revision}\n`;
    if (argv[0] === 'nix' && argv[1] === 'build') out = `${closure}\n`;
    if (argv[0] === 'nix' && argv[1] === 'eval') out = 'true\n';
    if (argv[0] === 'nixos-rebuild') out = '42 2026-10-13 NixOS kernel revision [] True\n';
    return { exitCode: 0, stdout: encoder.encode(out), stderr: encoder.encode('') };
  };
  const { rebuild } = await import('./runtime.mjs');
  assert.equal(rebuild(), 0);
  const build = commands.findIndex(argv => argv[0] === 'nix' && argv[1] === 'build');
  const profile = commands.findIndex(argv => argv[0] === 'nix-env' && argv.includes('/nix/var/nix/profiles/system'));
  const activate = commands.findIndex(argv => argv[0] === `${closure}/bin/switch-to-configuration`);
  const environment = commands.findIndex(argv => argv.includes('/nix/store/fixture-environment-switch'));
  assert(build >= 0 && build < profile && profile < activate && activate < environment);
  assert(commands[build].some(word => word.includes(`git+file://${system}?rev=${revision}`)));
  assert(commands[build].includes(`git+file://${firn}?rev=${revision}`));
  const user = commands[environment];
  assert.deepEqual(user.slice(0, 6), ['setpriv', '--no-new-privs', 'runuser', '-u', 'tom', '--']);
  assert(user.includes('HOME=/home/tom') && user.includes('XDG_RUNTIME_DIR=/run/user/1000'));
  assert(!commands.some(argv => argv[0] === 'sudo'));
  const validation = commands.find(argv => argv.includes('validate'));
  assert.deepEqual(validation.slice(0, 6), user.slice(0, 6));
  console.log('ok: existing bundled core builds fixed snapshots, selects system profile, switches exact closure, then unprivileged fixed user helper');
} finally {
  rmSync(root, { recursive: true });
}
