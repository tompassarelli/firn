// SPDX-License-Identifier: MIT OR Apache-2.0

import {
  closeSync,
  lstatSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';

const modulePath = process.env.FIRN_REPO_BUILD_MODULE
  ?? new URL('../lib/firn-repo-build.js', import.meta.url).pathname;
const { run } = await import(modulePath);

function errno(error) {
  return Math.abs(Number(error?.errno ?? 1));
}

function result(status, value = null) {
  return Object.freeze({ status, value });
}

const bridge = Object.freeze({
  env(name) { return process.env[name] ?? null; },
  out(text) { process.stdout.write(text); },
  err(text) { process.stderr.write(text); },
  status(value) { return value.status; },
  value(value) { return value.value; },
  exitStatus(value) { return value.exitStatus; },
  stdout(value) { return value.stdout; },
  stderr(value) { return value.stderr; },
  seconds(value) { return value.seconds; },
  nanoseconds(value) { return value.nanoseconds; },
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
  mtimeNanoseconds(path) {
    try {
      const value = statSync(path, { bigint: true }).mtimeNs;
      return result(0, Object.freeze({
        seconds: Number(value / 1_000_000_000n),
        nanoseconds: Number(value % 1_000_000_000n),
      }));
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
  writeTextAtomic(path, text) {
    const temporary = `${path}.firn-${process.pid}-${crypto.randomUUID()}.tmp`;
    try {
      writeFileSync(temporary, text, { flag: 'wx', mode: 0o600 });
      renameSync(temporary, path);
      return 0;
    } catch (error) {
      try { unlinkSync(temporary); } catch {}
      return errno(error);
    }
  },
  removeFile(path) {
    try {
      unlinkSync(path);
      return 0;
    } catch (error) {
      return errno(error);
    }
  },
  renameFile(source, destination) {
    try {
      renameSync(source, destination);
      return 0;
    } catch (error) {
      return errno(error);
    }
  },
  createTemporarySibling(destination) {
    const temporary = `${destination}.firn-${process.pid}-${crypto.randomUUID()}.tmp`;
    try {
      closeSync(openSync(temporary, 'wx', 0o600));
      return result(0, temporary);
    } catch (error) {
      return result(errno(error));
    }
  },
  runCapture(argv, maximum) {
    try {
      const child = Bun.spawnSync(argv, { stdout: 'pipe', stderr: 'pipe' });
      const stdout = child.stdout.toString();
      const stderr = child.stderr.toString();
      if (Buffer.byteLength(stdout) + Buffer.byteLength(stderr) > maximum) {
        return result(27);
      }
      return result(0, Object.freeze({
        exitStatus: child.exitCode,
        stdout,
        stderr,
      }));
    } catch (error) {
      return result(errno(error));
    }
  },
});

process.exitCode = run(bridge, Bun.argv.slice(2));
