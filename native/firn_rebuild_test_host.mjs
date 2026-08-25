// SPDX-License-Identifier: MIT OR Apache-2.0

const impact = await import(process.env.FIRN_IMPACT_TEST_MODULE);
const rebuild = await import(process.env.FIRN_REBUILD_TEST_MODULE);
process.exitCode = impact['run-tests']() + rebuild['run-tests']();
