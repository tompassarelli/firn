import { appendFileSync, readFileSync, watch } from 'node:fs';
import { createHash } from 'node:crypto';

import * as mailboxLogic from './cross-supervisor-mailbox-logic.js';

const peerOpenFacts = mailboxLogic['peer-open-facts'];
const receivedFacts = mailboxLogic['received-facts'];
const maximumTimeoutMilliseconds = 300_000;
const maximumRounds = 32;
const defaultTimeoutMilliseconds = 300_000;
const defaultRounds = 2;
// Keep successive writes on distinct file-event turns. Each owned write also
// schedules one bounded catch-up read because fs.watch may coalesce the peer's
// immediately correlated write into the notification already being handled.
const fileEventSeparationMilliseconds = 10;

function fail(message, status = 2) {
  process.stderr.write(`cross-supervisor-mailbox: ${message}\n`);
  process.exit(status);
}

function parseArguments(argv) {
  if (argv[0] !== 'duplex') {
    fail('usage: duplex --mailbox PATH --local NAME --peer NAME --message TEXT [--timeout-ms N] [--rounds N]');
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
    '--mailbox', '--local', '--peer', '--message', '--timeout-ms', '--rounds',
  ]);
  for (const [option, value] of values) {
    if (!allowed.has(option)) fail(`unknown option: ${option}`);
    if (/[\r\n\[\]]/.test(value)) fail(`${option} contains a mailbox delimiter`);
  }
  for (const option of ['--mailbox', '--local', '--peer', '--message']) {
    if (!values.get(option)) fail(`missing ${option}`);
  }
  const timeoutMilliseconds = values.has('--timeout-ms')
    ? Number(values.get('--timeout-ms'))
    : defaultTimeoutMilliseconds;
  if (!Number.isSafeInteger(timeoutMilliseconds)
      || timeoutMilliseconds < 1
      || timeoutMilliseconds > maximumTimeoutMilliseconds) {
    fail(`--timeout-ms must be an integer from 1 to ${maximumTimeoutMilliseconds}`);
  }
  const rounds = values.has('--rounds')
    ? Number(values.get('--rounds'))
    : defaultRounds;
  if (!Number.isSafeInteger(rounds) || rounds < 1 || rounds > maximumRounds) {
    fail(`--rounds must be an integer from 1 to ${maximumRounds}`);
  }
  if (values.get('--local') === values.get('--peer')) {
    fail('--local and --peer must differ');
  }
  return Object.freeze({
    mailbox: values.get('--mailbox'),
    local: values.get('--local'),
    peer: values.get('--peer'),
    channel: stableChannel(values.get('--local'), values.get('--peer')),
    timeoutMilliseconds,
    rounds,
    message: values.get('--message'),
  });
}

function stableChannel(local, peer) {
  const pair = local < peer ? [local, peer] : [peer, local];
  const digest = createHash('sha256').update(JSON.stringify(pair)).digest('hex');
  return `pair-${digest}`;
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
    const peerByRound = new Map();
    const repliedPeerEvents = new Set();
    const seenReceiptEvents = new Set();
    let nextRound = 1;
    let cursor = 0;
    let settled = false;
    let timeoutHandle;
    let watcher;

    const scheduleCausalCatchUp = () => {
      setTimeout(() => {
        if (!settled) inspectFuture();
      }, fileEventSeparationMilliseconds * 2);
    };

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
        `- [${at}][${options.channel}][${options.local} -> ${options.peer}][OPEN] event=${open.event} session=${session} round=${round} proof=${open.proof} expires=${open.expires} message=${options.message}`);
      scheduleCausalCatchUp();
      process.stderr.write(`OPENED event=${open.event} timestamp=${at} round=${round}\n`);
      return open;
    };

    const maybeAdvance = () => {
      while (nextRound <= options.rounds) {
        const own = ownByRound.get(nextRound);
        const peer = peerByRound.get(nextRound);
        if (!own?.receiptLine || !peer) return;
        process.stdout.write(`${JSON.stringify({
          channel: options.channel,
          round: nextRound,
          peerOpen: peer.openLine,
          peerMessage: peer.message,
          receipt: own.receiptLine,
        })}\n`);
        process.stderr.write(`ROUND-COMPLETE round=${nextRound}\n`);
        if (nextRound === options.rounds) {
          finish(0);
          return;
        }
        nextRound += 1;
        const rearmRound = nextRound;
        setTimeout(() => {
          if (settled) return;
          publishOpen(rearmRound);
          process.stderr.write(`REARMED round=${rearmRound}\n`);
        }, fileEventSeparationMilliseconds);
        return;
      }
    };

    const handlePeerOpen = line => {
      const facts = peerOpenFacts(
        line, options.channel, options.peer, options.local, Date.now(),
      );
      if (!Array.isArray(facts) || facts.length !== 7) return;
      const [, event, peerSession, roundText, proof, , message] = facts;
      const round = Number(roundText);
      if (!Number.isSafeInteger(round)
          || round < 1
          || round > options.rounds
          || repliedPeerEvents.has(event)
          || peerByRound.has(round)) return;
      repliedPeerEvents.add(event);
      setTimeout(() => {
        if (settled) return;
        try {
          const at = timestamp();
          const receipt = `- [${at}][${options.channel}][${options.local} -> ${options.peer}][RECEIVED] event=${newIdentity('event')} reply-to=${event} session=${session} round=${round} proof=${proof} received-session=${peerSession}`;
          appendLine(options.mailbox, receipt);
          scheduleCausalCatchUp();
          peerByRound.set(round, Object.freeze({ openLine: line, message }));
        } catch (error) {
          process.stderr.write(`ERROR ${error?.message ?? String(error)}\n`);
          finish(2);
          return;
        }
        maybeAdvance();
      }, fileEventSeparationMilliseconds);
    };

    const handlePeerReceipt = line => {
      const facts = receivedFacts(
        line, options.channel, options.peer, options.local,
      );
      if (!Array.isArray(facts) || facts.length !== 7) return;
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
        const facts = receivedFacts(
          line, options.channel, options.local, options.peer,
        );
        if (Array.isArray(facts) && facts.length === 7) {
          repliedPeerEvents.add(facts[2]);
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
        `ARMED channel=${options.channel} local=${options.local} peer=${options.peer} session=${session} rounds=${options.rounds} timeout_ms=${options.timeoutMilliseconds}\n`,
      );
      handleLines(baselineLines);
    } catch (error) {
      process.stderr.write(`ERROR ${error?.message ?? String(error)}\n`);
      finish(2);
      return;
    }

    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      process.stderr.write(`TIMEOUT channel=${options.channel}\n`);
      finish(124);
      return;
    }
    timeoutHandle = setTimeout(() => {
      process.stderr.write(`TIMEOUT channel=${options.channel}\n`);
      finish(124);
    }, remaining);
  });
}

const options = parseArguments(Bun.argv.slice(2));
process.exitCode = await runDuplex(options);
