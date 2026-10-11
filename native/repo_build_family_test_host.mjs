// SPDX-License-Identifier: MIT OR Apache-2.0

const build = await import(new URL('./firn/repo-build-test.js', import.meta.url));

process.exitCode = build["run-scenarios"]() === 0 ? 0 : 1;
