// SPDX-License-Identifier: MIT OR Apache-2.0

const inventory = await import(new URL('./firn/inventory-test.js', import.meta.url));
process.exitCode = inventory.test();
