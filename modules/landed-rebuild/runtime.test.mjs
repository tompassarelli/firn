import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = mkdtempSync(join(tmpdir(), 'firn-landed-effects-'));
try {
  const firn = join(root, 'firn');
  const system = join(root, 'system');
  const home = join(root, 'home');
  mkdirSync(`${home}/.local/bin`, { recursive: true });
  writeFileSync(`${home}/.local/bin/firn-schema`, '#!/bin/sh\nprintf schema-found\n', { mode: 0o755 });
  mkdirSync(`${firn}/.git`, { recursive: true });
  mkdirSync(`${system}/.git`, { recursive: true });
  Object.assign(process.env, {
    FIRN_REPO: firn, FIRN_SYSTEM_FLAKE: system, FIRN_SNAPSHOT_DIR: `${root}/validation`,
    FIRN_LANDED_USER: 'tom', FIRN_LANDED_HOME: home, FIRN_LANDED_UID: '1000',
    FIRN_LANDED_ENVIRONMENT_SWITCH: '/nix/store/fixture-environment-switch',
  });
  const commands = [];
  const revision = 'a'.repeat(40);
  const closure = `/nix/store/${'b'.repeat(32)}-system`;
  const encoder = new TextEncoder();
  const nativeSpawnSync = Bun.spawnSync;
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
  assert(user.includes(`HOME=${home}`) && user.includes('XDG_RUNTIME_DIR=/run/user/1000'));
  assert.equal(user.at(-1), `path:${firn}`);
  assert(!commands.some(argv => argv[0] === 'sudo'));
  const validation = commands.find(argv => argv.includes('validate'));
  assert.deepEqual(validation.slice(0, 6), user.slice(0, 6));
  const validationRoot = validation.findLast(word => word.startsWith('FIRN_REPO=')).slice('FIRN_REPO='.length);
  assert(validation.includes(`FIRN_VALIDATE_FLAKE=path:${validationRoot}`));
  const lookup = nativeSpawnSync({ cmd: [Bun.which('bash'), '-c', 'firn-schema'],
    env: { PATH: validation.find(word => word.startsWith('PATH=')).slice(5) },
    stdout: 'pipe', stderr: 'pipe' });
  assert.equal(lookup.exitCode, 0);
  assert.equal(new TextDecoder().decode(lookup.stdout), 'schema-found');
  const unit = `firn-agent-config-check-${revision}.service`;
  const advisory = commands.find(argv => argv[0] === 'bash' && argv[1] === '-c' && argv.includes(unit));
  assert(advisory, 'the advisory check is scheduled under a unit named for the snapshot');
  const bin = join(root, 'bin'), runtime = join(root, 'run'), ran = join(root, 'systemd-run');
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, 'systemd-run'), '#!/bin/sh\nprintf \'%s\\n\' "$@" > "$FAKE_RUN_LOG"\n', { mode: 0o755 });
  writeFileSync(join(bin, 'systemctl'), '#!/bin/sh\ncase "$*" in *is-active*) exit "${FAKE_ACTIVE:-1}" ;; esac\nexit 0\n', { mode: 0o755 });
  const runAdvisory = env => nativeSpawnSync({ cmd: advisory, env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, XDG_RUNTIME_DIR: runtime, FAKE_RUN_LOG: ran, ...env }, stdout: 'pipe', stderr: 'pipe' });
  const fragment = join(runtime, 'systemd', 'user', unit);
  mkdirSync(join(runtime, 'systemd', 'user'), { recursive: true });
  writeFileSync(fragment, 'left by an earlier attempt\n');
  assert.equal(runAdvisory({}).exitCode, 0, 'a stale check unit does not fail a retried deploy');
  assert(!existsSync(fragment), 'the stale runtime fragment is cleared');
  assert(readFileSync(ran, 'utf8').split('\n').includes(unit), 'the cleared unit is scheduled again');
  rmSync(ran);
  writeFileSync(fragment, 'still running\n');
  assert.equal(runAdvisory({ FAKE_ACTIVE: '0' }).exitCode, 0);
  assert(existsSync(fragment) && !existsSync(ran), 'a check already running is reused untouched');
  console.log('ok: existing bundled core builds fixed snapshots, selects system profile, switches exact closure, then unprivileged fixed user helper and an advisory check a retried deploy reuses or clears');
} finally {
  rmSync(root, { recursive: true });
}
