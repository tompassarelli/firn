// SPDX-License-Identifier: MIT OR Apache-2.0

const rebuild = await import(process.env.FIRN_REBUILD_TEST_MODULE);
process.exitCode = rebuild['run-properties'](process.env.CI ? 64 : 16);
