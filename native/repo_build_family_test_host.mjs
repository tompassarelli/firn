// SPDX-License-Identifier: MIT OR Apache-2.0

import { lstatSync, readFileSync, readdirSync } from 'node:fs';

const build = await import(new URL('./firn/repo-build-test.js', import.meta.url));
const flake = await import(new URL('./firn/flake-input-test.js', import.meta.url));
const flakeDriver = await import(new URL('./firn/flake-input-driver-test.js', import.meta.url));
const inventory = await import(new URL('./firn/inventory-test.js', import.meta.url));
const responsibility = await import(
  new URL('./firn/responsibility-projection-test.js', import.meta.url)
);

function errno(error) {
  return Math.abs(Number(error?.errno ?? 1));
}

function result(status, value = null) {
  return Object.freeze({ status, value });
}

const bridge = Object.freeze({
  status(value) { return value.status; },
  value(value) { return value.value; },
  listDirectory(path, maximum) {
    try {
      const names = readdirSync(path);
      return names.length > maximum ? result(27) : result(0, names);
    } catch (error) {
      return result(errno(error));
    }
  },
  pathKind(path) {
    try {
      const stat = lstatSync(path);
      return result(0, stat.isDirectory() ? 2 : stat.isSymbolicLink() ? 3 : 1);
    } catch (error) {
      return result(errno(error));
    }
  },
  readText(path, maximum) {
    try {
      const bytes = readFileSync(path);
      return bytes.length > maximum ? result(27) : result(0, bytes.toString('utf8'));
    } catch (error) {
      return result(errno(error));
    }
  },
});

const repo = process.argv[2];
const results = [
  build.test(),
  flake.test(),
  flakeDriver.test(),
  inventory.test(),
  responsibility.test(bridge, [repo]),
];
process.exitCode = results.every((status) => status === 0) ? 0 : 1;
