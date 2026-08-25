// SPDX-License-Identifier: MIT OR Apache-2.0

import {
  closeSync,
  constants,
  existsSync,
  fsyncSync,
  openSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { dirname } from 'node:path';

const maxBytes = 1024 * 1024;

function fail(message) {
  throw new Error(`activity assignment migration: ${message}`);
}

function readBounded(path) {
  const bytes = readFileSync(path);
  if (bytes.byteLength > maxBytes) fail(`${path} exceeds ${maxBytes} bytes`);
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

function validateJson(text) {
  let value;
  try { value = JSON.parse(text); }
  catch { fail('assignments.json is not valid JSON'); }
  if (value === null || Array.isArray(value) || typeof value !== 'object') {
    fail('assignments.json must be an object');
  }
  for (const [workspace, activity] of Object.entries(value)) {
    if (workspace.length === 0 || typeof activity !== 'string' || activity.length === 0) {
      fail('assignment names and activities must be non-empty strings');
    }
  }
  return value;
}

function parseLegacy(text) {
  let offset = 0;
  const entries = [];

  function skip() {
    while (offset < text.length) {
      if (/\s|,/u.test(text[offset])) { offset += 1; continue; }
      if (text[offset] === ';') {
        while (offset < text.length && text[offset] !== '\n') offset += 1;
        continue;
      }
      break;
    }
  }

  function string() {
    skip();
    if (text[offset] !== '"') fail(`expected a string at byte ${offset}`);
    offset += 1;
    let result = '';
    while (offset < text.length) {
      const character = text[offset++];
      if (character === '"') return result;
      if (character !== '\\') { result += character; continue; }
      if (offset >= text.length) fail('unterminated string escape');
      const escaped = text[offset++];
      const escapes = { '"': '"', '\\': '\\', n: '\n', r: '\r', t: '\t', b: '\b', f: '\f' };
      if (Object.hasOwn(escapes, escaped)) { result += escapes[escaped]; continue; }
      if (escaped === 'u') {
        const digits = text.slice(offset, offset + 4);
        if (!/^[0-9a-fA-F]{4}$/u.test(digits)) fail(`invalid unicode escape at byte ${offset}`);
        result += String.fromCharCode(Number.parseInt(digits, 16));
        offset += 4;
        continue;
      }
      fail(`unsupported string escape \\${escaped}`);
    }
    fail('unterminated string');
  }

  skip();
  if (text[offset++] !== '{') fail('legacy assignments must be an EDN map');
  skip();
  while (text[offset] !== '}') {
    if (offset >= text.length) fail('unterminated legacy assignment map');
    const workspace = string();
    const activity = string();
    if (workspace.length === 0 || activity.length === 0) {
      fail('assignment names and activities must be non-empty strings');
    }
    if (entries.some(([name]) => name === workspace)) {
      fail(`duplicate workspace assignment: ${workspace}`);
    }
    entries.push([workspace, activity]);
    skip();
  }
  offset += 1;
  skip();
  if (offset !== text.length) fail(`trailing legacy data at byte ${offset}`);
  entries.sort(([left], [right]) => left.localeCompare(right, 'en'));
  return Object.fromEntries(entries);
}

function writeExclusive(path, text) {
  let descriptor = -1;
  try {
    descriptor = openSync(path,
      constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
    writeFileSync(descriptor, text, 'utf8');
    fsyncSync(descriptor);
    closeSync(descriptor);
    descriptor = -1;
  } catch (error) {
    if (descriptor >= 0) closeSync(descriptor);
    try { unlinkSync(path); } catch {}
    throw error;
  }
}

function syncDirectory(path) {
  const descriptor = openSync(dirname(path), constants.O_RDONLY);
  try { fsyncSync(descriptor); } finally { closeSync(descriptor); }
}

export function migrate(legacyPath, jsonPath) {
  if (existsSync(jsonPath)) {
    validateJson(readBounded(jsonPath));
    return 'already-json';
  }
  if (!existsSync(legacyPath)) return 'no-legacy-state';

  const legacyText = readBounded(legacyPath);
  const assignments = parseLegacy(legacyText);
  const jsonText = `${JSON.stringify(assignments)}\n`;
  validateJson(jsonText);

  const rollbackPath = `${legacyPath}.rollback`;
  if (existsSync(rollbackPath)) {
    if (readBounded(rollbackPath) !== legacyText) {
      fail('existing rollback copy does not match legacy state');
    }
  } else {
    writeExclusive(rollbackPath, legacyText);
    syncDirectory(rollbackPath);
  }

  const temporary = `${jsonPath}.tmp.${process.pid}.${crypto.randomUUID()}`;
  try {
    writeExclusive(temporary, jsonText);
    validateJson(readBounded(temporary));
    renameSync(temporary, jsonPath);
    syncDirectory(jsonPath);
  } catch (error) {
    try { unlinkSync(temporary); } catch {}
    throw error;
  }
  return 'migrated';
}

if (import.meta.main) {
  const home = process.env.HOME ?? '/tmp';
  const stateRoot = process.env.XDG_STATE_HOME ?? `${home}/.local/state`;
  const legacyPath = process.argv[2] ?? `${stateRoot}/activity/assignments.edn`;
  const jsonPath = process.argv[3] ?? `${stateRoot}/activity/assignments.json`;
  try {
    process.stdout.write(`${migrate(legacyPath, jsonPath)}\n`);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
