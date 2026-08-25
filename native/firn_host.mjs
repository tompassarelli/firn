// SPDX-License-Identifier: MIT OR Apache-2.0

const modulePath = process.env.FIRN_DISPATCHER_MODULE
  ?? new URL('../lib/firn-dispatcher.js', import.meta.url).pathname;
const { run } = await import(modulePath);

const runtimeBin = process.env.FIRN_RUNTIME_BIN;
const bridge = Object.freeze({
  out(text) { process.stdout.write(text); },
  err(text) { process.stderr.write(text); },
  executeRuntime(name, args) {
    if (!runtimeBin) {
      process.stderr.write(
        'firn: FIRN_RUNTIME_BIN is not set by the user launcher\n',
      );
      return 127;
    }
    const child = Bun.spawnSync({
      cmd: [`${runtimeBin}/${name}`, ...args],
      env: process.env,
      stdin: 'inherit',
      stdout: 'inherit',
      stderr: 'inherit',
    });
    return child.exitCode;
  },
});

process.exitCode = run(bridge, Bun.argv.slice(2));
