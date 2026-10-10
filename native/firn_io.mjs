// SPDX-License-Identifier: MIT OR Apache-2.0

import { existsSync } from 'node:fs';

const clauseModule = process.env.FIRN_CLAUSE_HOST_LIST_MODULE;
const hostList = clauseModule ? await import(clauseModule) : undefined;

export function executeRuntime(name, args) {
  if (hostList?.handles(args)) {
    return hostList.run(process.env.FIRN_REPO, args);
  }
  const runtimeBin = process.env.FIRN_RUNTIME_BIN;
  if (!runtimeBin) {
    process.stderr.write(
      'firn: FIRN_RUNTIME_BIN is not set by the user launcher\n',
    );
    return 127;
  }
  const bundled = `${runtimeBin}/${name}`;
  return Bun.spawnSync({
    cmd: [existsSync(bundled) ? bundled : name, ...args],
    env: process.env,
    stdin: 'inherit',
    stdout: 'inherit',
    stderr: 'inherit',
  }).exitCode;
}
