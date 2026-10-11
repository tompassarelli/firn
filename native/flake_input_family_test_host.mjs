// SPDX-License-Identifier: MIT OR Apache-2.0

const pure = await import(new URL('./firn/flake-input-test.js', import.meta.url));
const driver = await import(
  new URL('./firn/flake-input-driver-test.js', import.meta.url)
);

const results = [pure["run-scenarios"](), driver["run-scenarios"]()];
process.exitCode = results.every((status) => status === 0) ? 0 : 1;
