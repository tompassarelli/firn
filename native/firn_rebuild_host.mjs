// SPDX-License-Identifier: MIT OR Apache-2.0

import { appendFileSync } from 'node:fs';

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
process.exitCode = run(Bun.argv.slice(2));
