// SPDX-License-Identifier: MIT OR Apache-2.0

const driver = await import(
  new URL('./firn/flake-input-driver-test.js', import.meta.url)
);

process.exitCode = driver["run-scenarios"]();
