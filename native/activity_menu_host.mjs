// SPDX-License-Identifier: MIT OR Apache-2.0

import { spawnSync } from 'node:child_process';

function errnoOf(error) {
  return Math.abs(Number(error?.errno ?? 5));
}

globalThis.activity_menu_host_get = (value, index) => value?.[index];
globalThis.activity_menu_host_call = (operation, args) => {
  if (operation === 'stderr') {
    process.stderr.write(args[0]);
    return null;
  }
  if (operation === 'capture') {
    const result = spawnSync(args[0][0], args[0].slice(1), {
      encoding: 'utf8', env: process.env, input: args[1], maxBuffer: args[2],
    });
    return result.error
      ? ['error', errnoOf(result.error)]
      : ['ok', result.status ?? 1, result.stdout ?? '', result.stderr ?? ''];
  }
  if (operation === 'inherit') {
    const result = spawnSync(args[0][0], args[0].slice(1), {
      env: process.env,
      stdio: 'inherit',
    });
    return result.error ? 126 : (result.status ?? 1);
  }
  throw new Error(`unknown activity-menu host operation: ${operation}`);
};

const modulePath = process.env.FIRN_ACTIVITY_MENU_MODULE
  ?? new URL('../lib/firn-activity/activity/menu.js', import.meta.url).pathname;
const { run } = await import(modulePath);
process.exitCode = run(Bun.argv.slice(2));
