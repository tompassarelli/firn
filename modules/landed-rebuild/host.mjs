import { existsSync, appendFileSync } from 'node:fs';
import { run } from './generated/firn/rebuild-family.js';

const decoder = new TextDecoder();
const username = process.env.FIRN_LANDED_USER;
const home = process.env.FIRN_LANDED_HOME;
const userEnv = ['env', '-i', `HOME=${home}`, `USER=${username}`, `LOGNAME=${username}`,
  `XDG_RUNTIME_DIR=/run/user/${process.env.FIRN_LANDED_UID}`,
  'PATH=/run/wrappers/bin:/run/current-system/sw/bin', 'GIT_CONFIG_COUNT=1',
  'GIT_CONFIG_KEY_0=safe.directory', 'GIT_CONFIG_VALUE_0=*', `FIRN_REPO=${process.env.FIRN_REPO}`];

export function argvFor(argv) {
  if (argv[0] === 'sudo') return argv.slice(1).length === 1 && argv[1] === '-v' ? ['true'] : argv.slice(1);
  if (argv[0] === 'env' && argv[2] === 'firn' && argv[3] === 'repo' && argv[4] === 'validate') {
    return ['setpriv', '--no-new-privs', 'runuser', '-u', username, '--', ...userEnv,
      argv[1], 'bash', `${home}/.local/share/firn/bin/firn`, 'repo', 'validate'];
  }
  if (argv[0] === 'firn-environment-switch') {
    return ['setpriv', '--no-new-privs', 'runuser', '-u', username, '--', ...userEnv,
      'bash', process.env.FIRN_LANDED_ENVIRONMENT_SWITCH, ...argv.slice(1)];
  }
  if (argv[0] === 'systemd-run') {
    return ['setpriv', '--no-new-privs', 'runuser', '-u', username, '--', ...userEnv, ...argv];
  }
  return argv;
}

globalThis.firn_host_get = (value, index) => value?.[index];
globalThis.firn_host_env = name => process.env[name] ?? null;
globalThis.firn_host_pid = () => process.pid;
globalThis.firn_host_out = text => process.stdout.write(text);
globalThis.firn_host_err = text => process.stderr.write(text);
globalThis.firn_host_git_checkout = path => existsSync(`${path}/.git`);
globalThis.firn_host_append = (path, text) => {
  try { appendFileSync(path, text); return ['ok']; }
  catch (error) { return ['error', Number(error?.errno ?? 5)]; }
};
globalThis.firn_host_capture = (argv, limit) => {
  try {
    const result = Bun.spawnSync({ cmd: argvFor(argv), env: process.env, stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' });
    if (result.stdout.byteLength > limit || result.stderr.byteLength > limit) return ['error', 27];
    return ['ok', result.exitCode, decoder.decode(result.stdout), decoder.decode(result.stderr)];
  } catch (error) { return ['error', Number(error?.errno ?? 5)]; }
};
globalThis.firn_host_inherit = argv => {
  try { return Bun.spawnSync({ cmd: argvFor(argv), env: process.env, stdin: 'inherit', stdout: 'inherit', stderr: 'inherit' }).exitCode; }
  catch { return 126; }
};

export function rebuild() {
  return run(['host', 'rebuild', 'whiterabbit']);
}

if (import.meta.main) {
  if (process.getuid() !== 0 || Bun.argv.length !== 2) {
    process.stderr.write('firn landed rebuild: root-owned fixed service entrypoint required\n');
    process.exitCode = 77;
  } else {
    process.exitCode = rebuild();
  }
}
