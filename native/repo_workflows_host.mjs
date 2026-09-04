// SPDX-License-Identifier: MIT OR Apache-2.0

import {
  closeSync,
  lstatSync,
  openSync,
  readSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';

globalThis.host_get = (value, key) => value?.[key];

const modulePath = process.env.FIRN_REPO_WORKFLOW_MODULE
  ?? new URL('../lib/firn/repo-workflows-runtime.js', import.meta.url).pathname;
const workflow = await import(modulePath);

function errnoOf(error) {
  return Math.abs(Number(error?.errno ?? 1));
}

function runCapture(argv, stdin, maxOutput) {
  const result = spawnSync(argv[0], argv.slice(1), {
    encoding: 'utf8',
    env: process.env,
    input: stdin,
    maxBuffer: maxOutput,
  });
  if (result.error) return { ok: false, errno: errnoOf(result.error) };
  return {
    ok: true,
    status: result.status ?? 1,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
}

function readTextBounded(path, maximum) {
  let fd;
  try {
    fd = openSync(path, 'r');
    const bytes = Buffer.alloc(maximum + 1);
    const count = readSync(fd, bytes, 0, bytes.length, 0);
    if (count > maximum) return { ok: false, errno: 27 };
    return { ok: true, text: bytes.subarray(0, count).toString('utf8') };
  } catch (error) {
    return { ok: false, errno: errnoOf(error) };
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function gitCapture(argv) {
  return runCapture(argv, '', 67108864);
}

function trimLineEnd(text) {
  return text.replace(/[\r\n]+$/, '');
}

function githubOrigin(origin, repo) {
  const forms = [
    `https://github.com/tompassarelli/${repo}`,
    `git@github.com:tompassarelli/${repo}`,
    `ssh://git@github.com/tompassarelli/${repo}`,
  ];
  return forms.some((form) => origin === form || origin === `${form}.git`);
}

function checkFirstPartyInput(name, locked) {
  const checkout = process.env.HOME
    ? `${process.env.HOME}/code/${locked.repo}/main`
    : null;
  if (!checkout) {
    process.stdout.write(
      `  ⚠ first-party input ${name}: HOME is unavailable; local checkout skipped (portable)\n`,
    );
    return 0;
  }
  let stat;
  try {
    stat = lstatSync(checkout);
  } catch (error) {
    if (errnoOf(error) === 2) {
      process.stdout.write(
        `  ⚠ first-party input ${name}: local checkout ${checkout} is absent; skipped (portable)\n`,
      );
      return 0;
    }
    process.stderr.write(
      `  ✗ first-party input ${name}: cannot inspect ${checkout}: errno ${errnoOf(error)}\n`,
    );
    return 1;
  }
  if (!stat.isDirectory()) {
    process.stderr.write(
      `  ✗ first-party input ${name}: local checkout is not a directory: ${checkout}\n`,
    );
    return 1;
  }
  const clean = gitCapture(['git', '-C', checkout, 'status', '--porcelain', '--untracked-files=no']);
  if (!clean.ok || clean.status !== 0 || clean.stdout !== '') return 1;
  const origin = gitCapture(['git', '-C', checkout, 'remote', 'get-url', 'origin']);
  if (!origin.ok || origin.status !== 0 || !githubOrigin(trimLineEnd(origin.stdout), locked.repo)) return 1;
  const main = gitCapture(['git', '-C', checkout, 'rev-parse', '--verify', 'refs/heads/main']);
  if (!main.ok || main.status !== 0) return 1;
  const mainRev = trimLineEnd(main.stdout);
  const ancestry = gitCapture(['git', '-C', checkout, 'merge-base', '--is-ancestor', locked.rev, mainRev]);
  if (ancestry.ok && ancestry.status === 0) {
    process.stdout.write(
      `  ✓ first-party input ${name}: pinned ${locked.rev} is an ancestor of local ${locked.repo}/main\n`,
    );
    return 0;
  }
  if (ancestry.ok && ancestry.status === 1) {
    process.stderr.write(
      `  ✗ first-party input ${name}: pinned ${locked.rev} is not an ancestor of local ${locked.repo}/main ${mainRev}\n`,
    );
    return 1;
  }
  return 1;
}

function checkFirstPartyInputSkew(root) {
  const lock = readTextBounded(`${root}/flake.lock`, 16777216);
  if (!lock.ok) {
    process.stderr.write(`firn doctor: cannot read flake.lock: errno ${lock.errno}\n`);
    return 1;
  }
  let document;
  try {
    document = JSON.parse(lock.text);
  } catch {
    process.stderr.write('firn doctor: invalid flake.lock JSON\n');
    return 1;
  }
  const inputs = document?.nodes?.root?.inputs;
  if (!inputs || Array.isArray(inputs) || typeof inputs !== 'object') {
    process.stderr.write('firn doctor: invalid flake.lock: root inputs must be an object\n');
    return 1;
  }
  for (const name of Object.keys(inputs).sort()) {
    if (typeof inputs[name] !== 'string') continue;
    const locked = document.nodes?.[inputs[name]]?.locked;
    if (locked?.type !== 'github' || locked?.owner !== 'tompassarelli') continue;
    const status = checkFirstPartyInput(name, locked);
    if (status !== 0) return status;
  }
  return 0;
}

const bridge = Object.freeze({
  env(name) { return process.env[name] ?? null; },
  out(text) { process.stdout.write(text); },
  err(text) { process.stderr.write(text); },
  runInherit(argv) {
    const result = spawnSync(argv[0], argv.slice(1), {
      env: process.env,
      stdio: 'inherit',
    });
    return result.error ? 127 : (result.status ?? 1);
  },
  runCapture,
  checkFirstPartyInputSkew,
  readTextBounded,
  pathKind(path) {
    try {
      const stat = lstatSync(path);
      return { ok: true, kind: stat.isDirectory() ? 2 : 1 };
    } catch (error) {
      return { ok: false, errno: errnoOf(error) };
    }
  },
  writeTextAtomic(path, text) {
    const temporary = `${path}.tmp.${process.pid}.${crypto.randomUUID()}`;
    try {
      writeFileSync(temporary, text);
      renameSync(temporary, path);
      return 0;
    } catch (error) {
      rmSync(temporary, { force: true });
      return errnoOf(error);
    }
  },
});

process.exitCode = workflow.run(bridge, Bun.argv.slice(2));
