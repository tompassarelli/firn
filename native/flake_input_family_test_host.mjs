// SPDX-License-Identifier: MIT OR Apache-2.0

const pure = await import(new URL('./firn/flake-input-test.js', import.meta.url));
const driver = await import(
  new URL('./firn/flake-input-driver-test.js', import.meta.url)
);

const results = [pure["run-properties"](process.env.CI ? 512 : 128), driver["run-properties"](process.env.CI ? 512 : 128)];
process.exitCode = results.every((status) => status === 0) ? 0 : 1;
