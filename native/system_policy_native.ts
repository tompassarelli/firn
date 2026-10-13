import * as policy from './system_policy.ts';
import { decode, encodeString, type JsonEvent } from './native_json.ts';

export type HostResult = { tag: 'ok'; text?: string; path?: string }
  | { tag: 'error'; errno: number };
export interface SystemPolicyBridge {
  getenv(name: string): string | null;
  readTextBounded(path: string, limit: number): HostResult;
  pathKind(path: string): HostResult;
  writeTextAtomic(path: string, text: string): HostResult;
  realPath(path: string): HostResult;
  readStdinBounded(limit: number): HostResult;
  out(text: string): void;
}
const maxHookBytes = 1048576;
const maxActivationBytes = 1048576;

type HookPayload = { toolName: string; command: string | null; filePath: string | null; sessionId: string };
function jsonValueEnd(events: JsonEvent[], start: number): number {
  if (start < 0 || start >= events.length) return -1;
  const event = events[start];
  if (event.tag === 'JsonObjectStart' || event.tag === 'JsonArrayStart') {
    const endTag = event.tag === 'JsonObjectStart' ? 'JsonObjectEnd' : 'JsonArrayEnd';
    let depth = 0;
    for (let index = start + 1; index < events.length; index++) {
      const nested = events[index];
      if (nested.tag === 'JsonObjectStart' || nested.tag === 'JsonArrayStart') depth++;
      else if (nested.tag === 'JsonObjectEnd' || nested.tag === 'JsonArrayEnd') {
        if (nested.tag === endTag && depth === 0) return index + 1;
        depth--;
      }
    }
    return -1;
  }
  return event.tag === 'JsonObjectEnd' || event.tag === 'JsonArrayEnd' || event.tag === 'JsonKey' ? -1 : start + 1;
}
function objectField(events: JsonEvent[], objectStart: number, wanted: string): number {
  for (let index = objectStart + 1; index < events.length;) {
    const event = events[index];
    if (event.tag !== 'JsonKey') return -1;
    const valueIndex = index + 1;
    const next = jsonValueEnd(events, valueIndex);
    if (next < 0) return -1;
    if (event.value === wanted) return valueIndex;
    index = next;
  }
  return -1;
}
function objectStringField(events: JsonEvent[], objectStart: number, wanted: string): string | null {
  const value = events[objectField(events, objectStart, wanted)];
  return value?.tag === 'JsonString' ? value.value : null;
}
function objectBoolField(events: JsonEvent[], objectStart: number, wanted: string): boolean | null {
  const value = events[objectField(events, objectStart, wanted)];
  return value?.tag === 'JsonBoolean' ? value.value : null;
}
function objectFieldStart(events: JsonEvent[], objectStart: number, wanted: string, tag: 'JsonObjectStart' | 'JsonArrayStart'): number {
  const index = objectField(events, objectStart, wanted);
  return events[index]?.tag === tag ? index : -1;
}
function decodeHookPayload(text: string): HookPayload | null {
  const decoded = decode(text);
  if (decoded.tag === 'JsonDecodeError') return null;
  const events = decoded.events;
  if (events.length === 0 || jsonValueEnd(events, 0) !== events.length || events[0].tag !== 'JsonObjectStart') return null;
  const toolInput = objectFieldStart(events, 0, 'tool_input', 'JsonObjectStart');
  const tool = objectStringField(events, 0, 'tool_name');
  const session = objectStringField(events, 0, 'session_id');
  const command = toolInput < 0 ? null : objectStringField(events, toolInput, 'command');
  const snakePath = toolInput < 0 ? null : objectStringField(events, toolInput, 'file_path');
  const camelPath = toolInput < 0 ? null : objectStringField(events, toolInput, 'filePath');
  return { toolName: tool ?? '', command, filePath: snakePath !== null ? snakePath : camelPath, sessionId: session ?? 'nosession' };
}
function activationPath(bridge: SystemPolicyBridge): string | null {
  const explicit = bridge.getenv('NORTH_AGENT_STATE_ROOT');
  if (explicit !== null && explicit !== '') return `${explicit}/current/activation.json`;
  const home = bridge.getenv('HOME');
  return home === null || home === '' ? null : `${home}/.local/state/north/agents/current/activation.json`;
}
function activationUnitActiveEvents(events: JsonEvent[], unitsStart: number, wantedKind: string, wantedId: string): boolean {
  let matched = false;
  let active = false;
  let valid = true;
  for (let index = unitsStart + 1; index < events.length && valid;) {
    const event = events[index];
    if (event.tag === 'JsonArrayEnd') return matched && active;
    if (event.tag !== 'JsonObjectStart') return false;
    const next = jsonValueEnd(events, index);
    const kind = objectStringField(events, index, 'kind');
    const id = objectStringField(events, index, 'id');
    const permission = objectStringField(events, index, 'permission');
    const unitActive = objectBoolField(events, index, 'active');
    const wanted = kind === wantedKind && id === wantedId;
    if (next < 0) return false;
    valid = !((matched && wanted) || (wanted && (permission === null || unitActive === null)));
    matched = matched || wanted;
    active = wanted ? permission === 'on' && unitActive === true : active;
    index = next;
  }
  return false;
}
function activationUnitActive(text: string, wantedKind: string, wantedId: string): boolean {
  const decoded = decode(text);
  if (decoded.tag === 'JsonDecodeError') return false;
  const events = decoded.events;
  if (events.length === 0 || jsonValueEnd(events, 0) !== events.length || events[0].tag !== 'JsonObjectStart') return false;
  const schema = objectStringField(events, 0, 'schema');
  const catalogDigest = objectStringField(events, 0, 'catalogDigest');
  const generationId = objectStringField(events, 0, 'generationId');
  const units = objectFieldStart(events, 0, 'units', 'JsonArrayStart');
  return schema === 'north.agent-activation/v1' && catalogDigest !== null && generationId !== null
    && units >= 0 && activationUnitActiveEvents(events, units, wantedKind, wantedId);
}
function guardsOff(bridge: SystemPolicyBridge): boolean {
  const value = bridge.getenv('AGENT_NO_AUTHORING_HOOKS');
  if (value !== null && value !== '') return value !== '0' && value !== 'false';
  const path = activationPath(bridge);
  if (path === null) return true;
  const result = bridge.readTextBounded(path, maxActivationBytes);
  return result.tag !== 'ok' || !activationUnitActive(String(result.text), 'hook', 'firn-system-policy');
}
function safeSessionId(sessionId: string): string {
  return new TextDecoder().decode(Uint8Array.from(new TextEncoder().encode(sessionId), byte =>
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57)
    || byte === 95 || byte === 46 || byte === 45 ? byte : 95));
}
function introUnseen(bridge: SystemPolicyBridge, sessionId: string): boolean {
  const runtime = bridge.getenv('XDG_RUNTIME_DIR');
  const directory = runtime === null || runtime === '' ? '/tmp' : runtime;
  const marker = `${directory}/firn-system-policy.${safeSessionId(sessionId)}`;
  const result = bridge.pathKind(marker);
  if (result.tag === 'ok' || result.errno !== 2) return false;
  bridge.writeTextAtomic(marker, '');
  return true;
}
function canonicalHookPath(bridge: SystemPolicyBridge, path: string): string {
  const result = bridge.realPath(path);
  return result.tag === 'ok' ? String(result.path) : path;
}
function emitDecision(bridge: SystemPolicyBridge, decision: policy.HookDecision): number {
  if (decision.tag === 'HookInject') bridge.out('{"hookSpecificOutput":{"hookEventName":"PreToolUse",'
    + '"additionalContext":' + encodeString(decision.context) + '}}\n');
  else if (decision.tag === 'HookRefuse') bridge.out('{"hookSpecificOutput":{"hookEventName":"PreToolUse",'
    + '"permissionDecision":"deny","permissionDecisionReason":' + encodeString(decision.reason) + '}}\n');
  return 0;
}
function handlePayload(bridge: SystemPolicyBridge, text: string): number {
  if (guardsOff(bridge)) return 0;
  const payload = decodeHookPayload(text);
  if (payload === null) return 0;
  const resolvedPath = payload.filePath !== null ? canonicalHookPath(bridge, payload.filePath) : null;
  const unseen = resolvedPath !== null && ['Edit', 'Write', 'MultiEdit'].includes(payload.toolName)
    && policy.firnPath(resolvedPath) ? introUnseen(bridge, payload.sessionId) : false;
  return emitDecision(bridge, policy.decideHook({ toolName: payload.toolName, command: payload.command,
    filePath: resolvedPath, sessionId: payload.sessionId, payloadOversized: false, guardsOff: false, introUnseen: unseen }));
}
export function run(bridge: SystemPolicyBridge): number {
  const result = bridge.readStdinBounded(maxHookBytes);
  return result.tag === 'ok' ? handlePayload(bridge, String(result.text)) : 0;
}
