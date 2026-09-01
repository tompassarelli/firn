import { appendFileSync, readFileSync, watch } from 'node:fs';

import * as mailboxLogic from './cross-supervisor-mailbox-logic.js';

const lineMatches = mailboxLogic['mailbox-line-matches?'];
const statuses = new Set(['ACK', 'PING']);
const maximumTimeoutMilliseconds = 300_000;

function fail(message, status = 2) {
  process.stderr.write(`cross-supervisor-mailbox: ${message}\n`);
  process.exit(status);
}

function parseArguments(argv) {
  const mode = argv[0];
  if (mode !== 'open-watch' && mode !== 'reply') {
    fail('usage: open-watch|reply --mailbox PATH --coordination ID --sender NAME --receiver NAME --status ACK|PING --timeout-ms N [--proof TOKEN] [--message TEXT]');
  }
  const values = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const option = argv[index];
    const value = argv[index + 1];
    if (!option?.startsWith('--') || value === undefined) {
      fail(`invalid argument at position ${index + 1}`);
    }
    if (values.has(option)) fail(`duplicate option: ${option}`);
    values.set(option, value);
  }
  const required = ['--mailbox', '--coordination', '--sender', '--receiver', '--status'];
  if (mode === 'open-watch') required.push('--timeout-ms');
  if (mode === 'reply') required.push('--proof');
  for (const option of required) {
    if (!values.get(option)) fail(`missing ${option}`);
  }
  for (const [option, value] of values) {
    if (!['--mailbox', '--coordination', '--sender', '--receiver', '--status', '--timeout-ms', '--proof', '--message'].includes(option)) {
      fail(`unknown option: ${option}`);
    }
    if (/[\r\n\]]/.test(value)) fail(`${option} contains a mailbox delimiter`);
  }
  const status = values.get('--status');
  if (!statuses.has(status)) fail('--status must be ACK or PING');
  const timeoutMilliseconds = mode === 'open-watch'
    ? Number(values.get('--timeout-ms'))
    : 0;
  if (mode === 'open-watch'
      && (!Number.isSafeInteger(timeoutMilliseconds)
          || timeoutMilliseconds < 1
          || timeoutMilliseconds > maximumTimeoutMilliseconds)) {
    fail(`--timeout-ms must be an integer from 1 to ${maximumTimeoutMilliseconds}`);
  }
  const proof = values.get('--proof');
  if (proof && /\s/.test(proof)) fail('--proof must not contain whitespace');
  return Object.freeze({
    mode,
    mailbox: values.get('--mailbox'),
    coordination: values.get('--coordination'),
    sender: values.get('--sender'),
    receiver: values.get('--receiver'),
    status,
    timeoutMilliseconds,
    proof,
    message: values.get('--message') ?? (mode === 'reply' ? 'received' : 'receipt requested'),
  });
}

function newIdentity(prefix) {
  return `${prefix}-${crypto.randomUUID()}`;
}

function timestamp() {
  return new Date().toISOString();
}

function mailboxLine({ coordination, sender, receiver, status, event, proof, message, at }) {
  return `- [${at}][${coordination}][${sender} -> ${receiver}][${status}] event=${event} proof=${proof} ${message}`;
}

function appendLine(path, line) {
  appendFileSync(path, `${line}\n`, { encoding: 'utf8', mode: 0o600 });
}

function matchingLine(text, options) {
  for (const line of text.split(/\r?\n/)) {
    if (lineMatches(
      line,
      options.coordination,
      options.receiver,
      options.sender,
      options.proof,
      options.status,
    )) return line;
  }
  return null;
}

function publishOpen(options, retryOf = null) {
  const at = timestamp();
  const event = newIdentity('event');
  const proof = options.proof ?? newIdentity('proof');
  const message = retryOf
    ? `${options.message} retry-of=${retryOf}`
    : options.message;
  const line = mailboxLine({
    ...options,
    status: 'OPEN',
    event,
    proof,
    message,
    at,
  });
  appendLine(options.mailbox, line);
  process.stderr.write(`OPENED event=${event} timestamp=${at} proof=${proof}\n`);
  return Object.freeze({ event, proof });
}

function armOnce(options, request, deadline) {
  return new Promise(resolve => {
    let cursor = 0;
    let settled = false;
    let timeoutHandle;
    const finish = result => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutHandle);
      watcher.close();
      resolve(result);
    };
    const inspectFuture = () => {
      let text;
      try {
        text = readFileSync(options.mailbox, 'utf8');
      } catch (error) {
        finish({ kind: 'error', error });
        return;
      }
      if (text.length < cursor) {
        cursor = text.length;
        return;
      }
      const appended = text.slice(cursor);
      const completeEnd = appended.lastIndexOf('\n');
      if (completeEnd < 0) return;
      cursor += completeEnd + 1;
      const line = matchingLine(appended.slice(0, completeEnd), {
        ...options,
        proof: request.proof,
      });
      if (line) finish({ kind: 'match', line });
    };
    let watcher;
    try {
      watcher = watch(options.mailbox, { persistent: true }, inspectFuture);
      watcher.on('error', error => finish({ kind: 'error', error }));
      const baseline = readFileSync(options.mailbox, 'utf8');
      cursor = baseline.length;
      const racedLine = matchingLine(baseline, { ...options, proof: request.proof });
      if (racedLine) {
        finish({ kind: 'pre-arm-race' });
        return;
      }
    } catch (error) {
      if (watcher) watcher.close();
      resolve({ kind: 'error', error });
      return;
    }
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      finish({ kind: 'timeout' });
      return;
    }
    timeoutHandle = setTimeout(() => finish({ kind: 'timeout' }), remaining);
    process.stderr.write(
      `ARMED coordination=${options.coordination} peer=${options.receiver} receiver=${options.sender} status=${options.status} timeout_ms=${remaining}\n`,
    );
  });
}

async function openAndWatch(options) {
  const deadline = Date.now() + options.timeoutMilliseconds;
  let request = publishOpen(options);
  while (true) {
    const result = await armOnce(options, request, deadline);
    if (result.kind === 'match') {
      process.stdout.write(`${result.line}\n`);
      return 0;
    }
    if (result.kind === 'pre-arm-race') {
      process.stderr.write(`PREARM-RETRY event=${request.event}\n`);
      request = publishOpen({ ...options, proof: null }, request.event);
      continue;
    }
    if (result.kind === 'timeout') {
      process.stderr.write(`TIMEOUT coordination=${options.coordination}\n`);
      return 124;
    }
    process.stderr.write(`ERROR ${result.error?.message ?? String(result.error)}\n`);
    return 2;
  }
}

function reply(options) {
  const line = mailboxLine({
    ...options,
    event: newIdentity('event'),
    proof: options.proof,
    at: timestamp(),
  });
  appendLine(options.mailbox, line);
  process.stdout.write(`${line}\n`);
  return 0;
}

const options = parseArguments(Bun.argv.slice(2));
process.exitCode = options.mode === 'reply'
  ? reply(options)
  : await openAndWatch(options);
