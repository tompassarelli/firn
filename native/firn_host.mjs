// SPDX-License-Identifier: MIT OR Apache-2.0

import { dirname } from 'node:path';
import { executeRuntime } from './firn_io.mjs';

const runtimeBin = process.env.FIRN_RUNTIME_BIN ?? '';
const galileo = process.env.FIRN_GALILEO ?? `${runtimeBin}/galileo`;
const dispatch = process.env.FIRN_GALILEO_DISPATCH ?? `${runtimeBin}/../lib/firn/dispatch.gal`;

function query(question) {
  const child = Bun.spawnSync({ cwd: dirname(dirname(dirname(dispatch))), cmd: [galileo, 'query', dispatch, question, '--json'], stdout: 'pipe', stderr: 'pipe' });
  if (child.exitCode !== 0) {
    process.stderr.write(`firn: galileo query failed\n${new TextDecoder().decode(child.stderr)}`);
    process.exit(127);
  }
  return JSON.parse(new TextDecoder().decode(child.stdout));
}

const commands = query('all ?order, ?node, ?edge, ?executable, ?arguments, ?required, ?usage, ?summary, ?gap where ?command is number ?order and ?command walks ?node then ?edge and ?command plans ?executable with ?arguments and ?command needs leaf ?required and ?command takes ?usage and ?command is summarized as ?summary after ?gap, sorted by ?order');

const find = (node, edge) => commands.find(c => c.node === node && c.edge === edge);
const nodeKnown = node => commands.some(c => c.node === node);
const nodeNames = () => [...new Set(commands.map(c => c.node))];
const usageOf = c => c.usage === '' ? c.edge : `${c.edge} ${c.usage}`;
const execution = (c, leaf) => ({ executable: c.executable, arguments: [c.node, c.edge, ...leaf] });
const planned = c => ({ executable: c.executable, arguments: c.arguments });
const error = message => ({ message, status: 1, descriptor: 2 });
const help = message => ({ message, status: 0, descriptor: 1 });
const missingLeaf = c => error(`firn: '${c.node} ${c.edge}' requires a leaf node\nUsage: firn ${c.node} ${c.edge} ${c.usage}\n  ${c.summary}\n`);
const unknownWalk = (node, edge) => `firn: unknown walk '${node} ${edge}'\n` + (nodeKnown(node)
  ? `  edges on '${node}': ${commands.filter(c => c.node === node).map(c => c.edge).join(', ')}\n`
  : `  no such node '${node}'\n  available nodes: ${nodeNames().join(', ')}\n`);
const nodeHelp = node => commands.filter(c => c.node === node)
  .reduce((text, c) => `${text}  firn ${c.node} ${usageOf(c)}\n      ${c.summary}\n`, `Edges on '${node}':\n`);

function fullHelp() {
  const common = query('all ?order, ?node, ?label, ?summary, ?gap where ?command is common command ?order as ?label summarized as ?summary after ?gap and ?command walks ?node then ?edge, sorted by ?order')
    .map(c => `  firn ${c.node} ${c.label}${c.gap}${c.summary}\n`).join('');
  let graph = '';
  for (const node of nodeNames()) {
    graph += `${node}\n` + commands.filter(c => c.node === node).map(c => `  ${usageOf(c)}${c.gap}${c.summary}\n`).join('') + '\n';
  }
  return `firn — config management with galileo\n\nUsage:\n  firn <node> <edge> [<leaf>]  [<node> <edge> [<leaf>] ...]\n\nOperator shortcuts:\n  firn rebuild [host] [--dry-run]  review + build + validate + switch\n  firn rollback <generation>      activate one exact prior generation\n\nCommon graph commands:\n${common}\nFull graph:\n\n${graph}`;
}

const prewarm = new Set(['--print-warm-key', '--plan-detached', '--plan-reference-transaction', '--reference-transaction', '--worker']);

function token(state, t) {
  switch (state.kind) {
    case 'start':
      if (t === 'help' || t === '-h' || t === '--help') return { kind: 'diagnostic', diagnostic: help(fullHelp()) };
      if (t === 'rebuild') return { kind: 'alias', command: find('host', 'rebuild'), usage: 'Usage: firn rebuild [host]\n' };
      if (t === 'rollback') return { kind: 'alias', command: find('host', 'rollback'), usage: 'Usage: firn rollback <generation>\n' };
      if (prewarm.has(t)) return { kind: 'prewarm', arguments: [t] };
      return { kind: 'node', steps: [], node: t };
    case 'plan':
      return { kind: 'node', steps: state.steps, node: t };
    case 'node': {
      const c = find(state.node, t);
      return c ? { kind: 'leaf', steps: state.steps, command: c } : { kind: 'diagnostic', diagnostic: error(unknownWalk(state.node, t)) };
    }
    case 'leaf':
      if (!state.command.required && nodeKnown(t)) return { kind: 'possible', steps: state.steps, command: state.command, node: t };
      return { kind: 'plan', steps: [...state.steps, execution(state.command, [t])] };
    case 'possible': {
      const c = find(state.node, t);
      if (!c) return { kind: 'node', steps: [...state.steps, execution(state.command, [state.node])], node: t };
      if (state.command.required) return { kind: 'diagnostic', diagnostic: missingLeaf(state.command) };
      return { kind: 'leaf', steps: [...state.steps, planned(state.command)], command: c };
    }
    case 'alias':
      if (t.startsWith('-')) return { kind: 'diagnostic', diagnostic: error(state.usage) };
      return { kind: 'complete', execution: execution(state.command, [t]), usage: state.usage };
    case 'complete':
      return { kind: 'diagnostic', diagnostic: error(state.usage) };
    case 'prewarm':
      return { kind: 'prewarm', arguments: [...state.arguments, t] };
    case 'diagnostic':
      return state;
  }
}

function finish(state) {
  switch (state.kind) {
    case 'start': return help(fullHelp());
    case 'plan': return { steps: state.steps };
    case 'node':
      if (state.steps.length > 0) return error(`firn: dangling token after a complete walk: ${state.node}\n`);
      return nodeKnown(state.node) ? help(nodeHelp(state.node))
        : error(`firn: incomplete walk; expected <node> <edge> [<leaf>]\n  available nodes: ${nodeNames().join(', ')}\n`);
    case 'leaf':
      return state.command.required ? missingLeaf(state.command) : { steps: [...state.steps, planned(state.command)] };
    case 'possible': return { steps: [...state.steps, execution(state.command, [state.node])] };
    case 'alias': return state.command.required ? error(state.usage) : { steps: [planned(state.command)] };
    case 'complete': return { steps: [state.execution] };
    case 'prewarm': return { steps: [{ executable: 'firn-prewarm', arguments: state.arguments }] };
    case 'diagnostic': return state.diagnostic;
  }
}

export function parseDispatch(args) {
  if ((args[0] === 'rebuild' || (args[0] === 'host' && args[1] === 'rebuild')) && args.includes('--dry-run')) {
    const words = args.filter(word => word !== '--dry-run');
    const leaf = words.slice(words[0] === 'host' ? 2 : 1);
    if (leaf.length <= 1 && leaf.every(word => !word.startsWith('-'))) {
      return { steps: [execution(find('host', 'rebuild'), [...leaf, '--dry-run'])] };
    }
  }
  return finish(args.reduce(token, { kind: 'start' }));
}

function run(args) {
  const result = parseDispatch(args);
  if ('message' in result) {
    process[result.descriptor === 1 ? 'stdout' : 'stderr'].write(result.message);
    return result.status;
  }
  let status = 0;
  for (const step of result.steps) {
    if (status !== 0) break;
    status = executeRuntime(step.executable, step.arguments);
  }
  return status;
}

if (import.meta.main) process.exitCode = run(Bun.argv.slice(2));
