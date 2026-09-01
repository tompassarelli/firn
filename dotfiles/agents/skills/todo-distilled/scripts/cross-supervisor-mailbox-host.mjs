import { appendFileSync, readFileSync, watch } from 'node:fs';

import * as mailboxLogic from './cross-supervisor-mailbox-logic.js';

const peerOpenFacts = mailboxLogic['peer-open-facts'];
const receiptFacts = mailboxLogic['receipt-facts'];
const statuses = new Set(['ACK', 'PING']);
const maximumTimeoutMilliseconds = 300_000;
const maximumRounds = 32;

function fail(message, status = 2) {
  process.stderr.write(`cross-supervisor-mailbox: ${message}\n`);
  process.exit(status);
}

function parseArguments(argv) {
  if (argv[0] !== 'duplex') {
    fail('usage: duplex --mailbox PATH --coordination ID --local NAME --peer NAME --status ACK|PING --timeout-ms N --rounds N [--message TEXT]');
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
  const allowed = new Set([
    '--mailbox', '--coordination', '--local', '--peer', '--status',
    '--timeout-ms', '--rounds', '--message',
  ]);
  for (const [option, value] of values) {
    if (!allowed.has(option)) fail(`unknown option: ${option}`);
    if (/[\r\n\]]/.test(value)) fail(`${option} contains a mailbox delimiter`);
  }
  for (const option of [
    '--mailbox', '--coordination', '--local', '--peer', '--status',
    '--timeout-ms', '--rounds',
  ]) {
    if (!values.get(option)) fail(`missing ${option}`);
  }
  const status = values.get('--status');
  if (!statuses.has(status)) fail('--status must be ACK or PING');
  const timeoutMilliseconds = Number(values.get('--timeout-ms'));
  if (!Number.isSafeInteger(timeoutMilliseconds)
      || timeoutMilliseconds < 1
      || timeoutMilliseconds > maximumTimeoutMilliseconds) {
    fail(`--timeout-ms must be an integer from 1 to ${maximumTimeoutMilliseconds}`);
  }
  const rounds = Number(values.get('--rounds'));
  if (!Number.isSafeInteger(rounds) || rounds < 1 || rounds > maximumRounds) {
    fail(`--rounds must be an integer from 1 to ${maximumRounds}`);
  }
  if (values.get('--local') === values.get('--peer')) {
    fail('--local and --peer must differ');
  }
  return Object.freeze({
    mailbox: values.get('--mailbox'),
    coordination: values.get('--coordination'),
    local: values.get('--local'),
    peer: values.get('--peer'),
    status,
    timeoutMilliseconds,
    rounds,
    message: values.get('--message') ?? 'cross-supervisor sync',
  });
}

function newIdentity(prefix) {
  return `${prefix}-${crypto.randomUUID()}`;
}

function timestamp() {
  return new Date().toISOString();
}

function appendLine(path, line) {
  appendFileSync(path, `${line}\n`, { encoding: 'utf8', mode: 0o600 });
}

function completeLines(text) {
  const completeEnd = text.lastIndexOf('\n');
  return completeEnd < 0
    ? []
    : text.slice(0, completeEnd).split(/\r?\n/);
}

function runDuplex(options) {
  return new Promise(resolve => {
    const startedAt = Date.now();
    const deadline = startedAt + options.timeoutMilliseconds;
    const session = newIdentity('session');
    const ownByEvent = new Map();
    const ownByRound = new Map();
    const peerRoundsHandled = new Set();
    const repliedPeerEvents = new Set();
    const seenReceiptEvents = new Set();
    let nextRound = 1;
    let cursor = 0;
    let settled = false;
    let timeoutHandle;
    let watcher;

    const finish = status => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutHandle);
      if (watcher) watcher.close();
      resolve(status);
    };

    const publishOpen = round => {
      const at = timestamp();
      const open = {
        event: newIdentity('event'),
        proof: newIdentity('proof'),
        round,
        expires: deadline,
        receiptLine: null,
      };
      ownByEvent.set(open.event, open);
      ownByRound.set(round, open);
      appendLine(options.mailbox,
        `- [${at}][${options.coordination}][${options.local} -> ${options.peer}][OPEN] event=${open.event} session=${session} round=${round} proof=${open.proof} expires=${open.expires} ${options.message}`);
      process.stderr.write(`OPENED event=${open.event} timestamp=${at} round=${round}\n`);
      return open;
    };

    const maybeAdvance = () => {
      while (nextRound <= options.rounds) {
        const own = ownByRound.get(nextRound);
        if (!own?.receiptLine || !peerRoundsHandled.has(nextRound)) return;
        process.stdout.write(`${own.receiptLine}\n`);
        process.stderr.write(`ROUND-COMPLETE round=${nextRound}\n`);
        if (nextRound === options.rounds) {
          finish(0);
          return;
        }
        nextRound += 1;
        publishOpen(nextRound);
        process.stderr.write(`REARMED round=${nextRound}\n`);
      }
    };

    const handlePeerOpen = line => {
      const facts = peerOpenFacts(
        line, options.coordination, options.peer, options.local, Date.now(),
      );
      if (!Array.isArray(facts) || facts.length !== 6) return;
      const [, event, peerSession, roundText, proof] = facts;
      const round = Number(roundText);
      if (!Number.isSafeInteger(round)
          || round < 1
          || round > options.rounds
          || repliedPeerEvents.has(event)) return;
      repliedPeerEvents.add(event);
      const at = timestamp();
      const receipt = `- [${at}][${options.coordination}][${options.local} -> ${options.peer}][${options.status}] event=${newIdentity('event')} reply-to=${event} session=${session} round=${round} proof=${proof} received-session=${peerSession}`;
      appendLine(options.mailbox, receipt);
      peerRoundsHandled.add(round);
      maybeAdvance();
    };

    const handlePeerReceipt = line => {
      const facts = receiptFacts(
        line, options.coordination, options.peer, options.local, options.status,
      );
      if (!Array.isArray(facts) || facts.length !== 6) return;
      const [, receiptEvent, replyTo, , roundText, proof] = facts;
      if (seenReceiptEvents.has(receiptEvent)) return;
      const own = ownByEvent.get(replyTo);
      const round = Number(roundText);
      if (!own
          || own.round !== round
          || own.proof !== proof
          || own.receiptLine) return;
      seenReceiptEvents.add(receiptEvent);
      own.receiptLine = line;
      maybeAdvance();
    };

    const handleLines = lines => {
      if (settled) return;
      for (const line of lines) {
        handlePeerOpen(line);
        handlePeerReceipt(line);
        if (settled) return;
      }
    };

    const rememberPriorReplies = lines => {
      for (const line of lines) {
        for (const status of statuses) {
          const facts = receiptFacts(
            line, options.coordination, options.local, options.peer, status,
          );
          if (Array.isArray(facts) && facts.length === 6) {
            repliedPeerEvents.add(facts[2]);
          }
        }
      }
    };

    const inspectFuture = () => {
      let text;
      try {
        text = readFileSync(options.mailbox, 'utf8');
      } catch (error) {
        process.stderr.write(`ERROR ${error?.message ?? String(error)}\n`);
        finish(2);
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
      handleLines(appended.slice(0, completeEnd).split(/\r?\n/));
    };

    try {
      watcher = watch(options.mailbox, { persistent: true }, inspectFuture);
      watcher.on('error', error => {
        process.stderr.write(`ERROR ${error?.message ?? String(error)}\n`);
        finish(2);
      });
      const baseline = readFileSync(options.mailbox, 'utf8');
      cursor = baseline.length;
      const baselineLines = completeLines(baseline);
      rememberPriorReplies(baselineLines);
      publishOpen(1);
      process.stderr.write(
        `ARMED coordination=${options.coordination} local=${options.local} peer=${options.peer} session=${session} rounds=${options.rounds} timeout_ms=${options.timeoutMilliseconds}\n`,
      );
      handleLines(baselineLines);
    } catch (error) {
      process.stderr.write(`ERROR ${error?.message ?? String(error)}\n`);
      finish(2);
      return;
    }

    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      process.stderr.write(`TIMEOUT coordination=${options.coordination}\n`);
      finish(124);
      return;
    }
    timeoutHandle = setTimeout(() => {
      process.stderr.write(`TIMEOUT coordination=${options.coordination}\n`);
      finish(124);
    }, remaining);
  });
}

const options = parseArguments(Bun.argv.slice(2));
process.exitCode = await runDuplex(options);
