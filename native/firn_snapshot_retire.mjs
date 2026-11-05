// SPDX-License-Identifier: MIT OR Apache-2.0

import { existsSync } from 'node:fs';

const terminations = [['SIGHUP', 1], ['SIGINT', 2], ['SIGTERM', 15]];

export function retireSnapshot(root, snapshot) {
  if (!existsSync(snapshot)) return true;
  const removed = Bun.spawnSync({ cmd: ['git', '-C', root, 'worktree', 'remove', '--force', snapshot], stdin: 'ignore', stdout: 'ignore', stderr: 'inherit' });
  return removed.exitCode === 0;
}

export function retireSnapshotsOnTermination(root, snapshots) {
  for (const [signal, number] of terminations) {
    process.on(signal, () => {
      for (const snapshot of snapshots()) retireSnapshot(root, snapshot);
      process.exit(128 + number);
    });
  }
}
