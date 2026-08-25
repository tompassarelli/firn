// SPDX-License-Identifier: MIT OR Apache-2.0

import {
  closeSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { basename, dirname, join } from 'node:path';

const modulePath = process.env.FIRN_TAG_MODULE
  ?? new URL('../lib/firn-tag.js', import.meta.url).pathname;
const { run } = await import(modulePath);

const errno = (error) => Math.abs(Number(error?.errno)) || 5;
const ok = (value) => Object.freeze({ status: 0, value });
const failed = (error) => Object.freeze({ status: errno(error), value: null });
let temporaryId = 0;

const bridge = Object.freeze({
  env(name) { return process.env[name] ?? null; },
  out(text) { process.stdout.write(text); },
  err(text) { process.stderr.write(text); },
  pathKind(path) {
    try {
      const info = lstatSync(path);
      return ok(info.isSymbolicLink() ? 3 : info.isDirectory() ? 2 : 1);
    } catch (error) {
      return failed(error);
    }
  },
  listDirectory(path, maximum) {
    try {
      const entries = readdirSync(path, { encoding: 'utf8' });
      return entries.length > maximum ? Object.freeze({ status: 7, value: null }) : ok(entries);
    } catch (error) {
      return failed(error);
    }
  },
  readText(path, maximum) {
    try {
      if (statSync(path).size > maximum) {
        return Object.freeze({ status: 27, value: null });
      }
      return ok(readFileSync(path, 'utf8'));
    } catch (error) {
      return failed(error);
    }
  },
  makeParentDirectories(path) {
    try {
      mkdirSync(dirname(path), { recursive: true });
      return 0;
    } catch (error) {
      return errno(error);
    }
  },
  writeTextAtomic(path, text) {
    const temporary = join(
      dirname(path),
      `.${basename(path)}.firn-${process.pid}-${temporaryId++}`,
    );
    let descriptor = null;
    try {
      descriptor = openSync(temporary, 'wx', 0o644);
      writeFileSync(descriptor, text, 'utf8');
      closeSync(descriptor);
      descriptor = null;
      renameSync(temporary, path);
      return 0;
    } catch (error) {
      if (descriptor !== null) {
        try { closeSync(descriptor); } catch {}
      }
      try { unlinkSync(temporary); } catch {}
      return errno(error);
    }
  },
});

process.exitCode = run(bridge, Bun.argv.slice(2));
