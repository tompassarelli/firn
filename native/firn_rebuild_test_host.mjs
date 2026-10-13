// SPDX-License-Identifier: MIT OR Apache-2.0

const rebuild = await import(process.env.FIRN_REBUILD_TEST_MODULE);
process.exitCode = rebuild.runProperties(process.env.CI ? 64 : 16);

const core = await import(new URL('./rebuild.ts', `file://${process.env.FIRN_REBUILD_TEST_MODULE}`));
const listing = await Bun.file(new URL('./fixtures/nixos-rebuild-26.05-2026-10-11-generations.txt', import.meta.url)).text();
const rows = listing.trim().split('\n').slice(1).map(line => line.trim().split(/\s+/));
const current = rows.find(row => row.at(-1) === 'True')[0];
if (core.currentGeneration(listing) !== current || rows.some(row => !core.generationPresent(listing,row[0]))) process.exitCode=1;
