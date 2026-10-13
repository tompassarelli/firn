export type JsonEvent =
  | { tag: 'JsonObjectStart'; offset: number }
  | { tag: 'JsonObjectEnd'; offset: number }
  | { tag: 'JsonArrayStart'; offset: number }
  | { tag: 'JsonArrayEnd'; offset: number }
  | { tag: 'JsonNull'; offset: number }
  | { tag: 'JsonKey'; offset: number; value: string }
  | { tag: 'JsonString'; offset: number; value: string }
  | { tag: 'JsonNumber'; offset: number; lexeme: string }
  | { tag: 'JsonBoolean'; offset: number; value: boolean };
export type JsonDecodeResult =
  | { tag: 'JsonDecoded'; events: JsonEvent[] }
  | { tag: 'JsonDecodeError'; offset: number; message: string };
export type JsonEncodeResult =
  | { tag: 'JsonEncoded'; text: string }
  | { tag: 'JsonEncodeError'; eventIndex: number; message: string };

const utf8Encoder = new TextEncoder();
const utf8Decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
function utf8Bytes(text: string): Uint8Array {
  if (typeof text !== 'string') throw new TypeError('utf8-encode requires a String');
  for (const character of text) {
    const point = character.codePointAt(0)!;
    if (point >= 0xd800 && point <= 0xdfff) throw new TypeError('utf8-encode requires Unicode scalar values');
  }
  return utf8Encoder.encode(text);
}
const whitespace = (byte: number) => byte === 32 || byte === 9 || byte === 10 || byte === 13;
const digit = (byte: number) => byte >= 48 && byte <= 57;
type Scan = { next: number; value: string } | { offset: number; message: string };

function stringToken(bytes: Uint8Array, start: number): Scan {
  const output: number[] = [];
  let at = start;
  const hex = (offset: number) => {
    if (offset + 4 > bytes.length) return -1;
    let value = 0;
    for (let index = offset; index < offset + 4; index++) {
      const byte = bytes[index];
      const nibble = byte >= 48 && byte <= 57 ? byte - 48 : byte >= 65 && byte <= 70 ? byte - 55 : byte >= 97 && byte <= 102 ? byte - 87 : -1;
      if (nibble < 0) return -1;
      value = value * 16 + nibble;
    }
    return value;
  };
  while (at < bytes.length) {
    const byte = bytes[at];
    if (byte === 34) return { next: at + 1, value: utf8Decoder.decode(new Uint8Array(output)) };
    if (byte < 32) return { offset: at, message: 'unescaped control character in string' };
    if (byte !== 92) { output.push(byte); at++; continue; }
    if (at + 1 >= bytes.length) return { offset: at, message: 'unterminated string escape' };
    const escaped = bytes[at + 1];
    const simple = new Map([[34, 34], [92, 92], [47, 47], [98, 8], [102, 12], [110, 10], [114, 13], [116, 9]]).get(escaped);
    if (simple !== undefined) { output.push(simple); at += 2; continue; }
    if (escaped !== 117) return { offset: at + 1, message: 'invalid string escape' };
    let point = hex(at + 2);
    if (point < 0) return { offset: at + 2, message: 'invalid four-digit Unicode escape' };
    let width = 6;
    if (point >= 0xd800 && point <= 0xdbff) {
      if (at + 12 > bytes.length || bytes[at + 6] !== 92 || bytes[at + 7] !== 117) return { offset: at, message: 'high surrogate is not followed by a low surrogate' };
      const low = hex(at + 8);
      if (low < 0xdc00 || low > 0xdfff) return { offset: at + 8, message: 'high surrogate is not followed by a low surrogate' };
      point = 0x10000 + (point - 0xd800) * 1024 + low - 0xdc00;
      width = 12;
    } else if (point >= 0xdc00 && point <= 0xdfff) return { offset: at, message: 'unpaired low surrogate' };
    output.push(...utf8Encoder.encode(String.fromCodePoint(point)));
    at += width;
  }
  return { offset: at, message: 'unterminated string' };
}

function numberToken(bytes: Uint8Array, start: number): Scan {
  let at = start + (bytes[start] === 45 ? 1 : 0);
  if (!digit(bytes[at])) return { offset: at, message: 'number requires an integer part' };
  if (bytes[at] === 48) {
    at++;
    if (digit(bytes[at])) return { offset: at, message: 'leading zero is not allowed in a number' };
  } else { while (digit(bytes[at])) at++; }
  if (bytes[at] === 46) {
    at++;
    if (!digit(bytes[at])) return { offset: at, message: 'fraction requires at least one digit' };
    while (digit(bytes[at])) at++;
  }
  if (bytes[at] === 69 || bytes[at] === 101) {
    at++;
    if (bytes[at] === 43 || bytes[at] === 45) at++;
    if (!digit(bytes[at])) return { offset: at, message: 'exponent requires at least one digit' };
    while (digit(bytes[at])) at++;
  }
  return { next: at, value: utf8Decoder.decode(bytes.subarray(start, at)) };
}

type Expectation = 'value' | 'objectFirst' | 'objectNext' | 'colon' | 'objectEnd' | 'arrayFirst' | 'arrayNext' | 'arrayEnd' | 'done';
export function decode(text: string): JsonDecodeResult {
  const bytes = utf8Bytes(text);
  const events: JsonEvent[] = [];
  const stack: Expectation[] = ['done'];
  let state: Expectation = 'value';
  let at = 0;
  const fail = (message: string, offset = at): JsonDecodeResult => ({ tag: 'JsonDecodeError', offset, message });
  const finish = () => { state = stack.pop()!; };
  while (true) {
    while (whitespace(bytes[at])) at++;
    const byte = bytes[at];
    switch (state) {
      case 'done': return at === bytes.length ? { tag: 'JsonDecoded', events } : fail('unexpected data after JSON value');
      case 'arrayFirst':
        if (byte === 93) { events.push({ tag: 'JsonArrayEnd', offset: at++ }); finish(); break; }
        state = 'value'; stack.push('arrayEnd'); break;
      case 'arrayNext': state = 'value'; stack.push('arrayEnd'); break;
      case 'objectFirst':
      case 'objectNext': {
        if (state === 'objectFirst' && at === bytes.length) return fail('unterminated object');
        if (state === 'objectFirst' && byte === 125) { events.push({ tag: 'JsonObjectEnd', offset: at++ }); finish(); break; }
        if (byte !== 34) return fail('object key must be a string');
        const token = stringToken(bytes, at + 1);
        if ('message' in token) return fail(token.message, token.offset);
        events.push({ tag: 'JsonKey', offset: at, value: token.value }); at = token.next; state = 'colon'; break;
      }
      case 'colon':
        if (byte !== 58) return fail("expected ':' after object key");
        at++; state = 'value'; stack.push('objectEnd'); break;
      case 'objectEnd':
      case 'arrayEnd': {
        const object = state === 'objectEnd';
        if (at === bytes.length) return fail(object ? 'unterminated object' : 'unterminated array');
        if (byte === 44) { at++; state = object ? 'objectNext' : 'arrayNext'; break; }
        if (byte !== (object ? 125 : 93)) return fail(object ? "expected ',' or '}' after object value" : "expected ',' or ']' after array value");
        events.push({ tag: object ? 'JsonObjectEnd' : 'JsonArrayEnd', offset: at++ }); finish(); break;
      }
      case 'value': {
        if (byte === 123 || byte === 91) { events.push({ tag: byte === 123 ? 'JsonObjectStart' : 'JsonArrayStart', offset: at++ }); state = byte === 123 ? 'objectFirst' : 'arrayFirst'; break; }
        if (byte === 34 || byte === 45 || digit(byte)) {
          const token = byte === 34 ? stringToken(bytes, at + 1) : numberToken(bytes, at);
          if ('message' in token) return fail(token.message, token.offset);
          events.push(byte === 34 ? { tag: 'JsonString', offset: at, value: token.value } : { tag: 'JsonNumber', offset: at, lexeme: token.value });
          at = token.next; finish(); break;
        }
        const literal = ['true', 'false', 'null'].find(word => word.split('').every((char, index) => bytes[at + index] === char.charCodeAt(0)));
        if (!literal) return fail('expected a JSON value');
        const end = at + literal.length;
        if (end < bytes.length && !whitespace(bytes[end]) && ![44, 93, 125].includes(bytes[end])) return fail(`invalid token after ${literal}`, end);
        events.push(literal === 'null' ? { tag: 'JsonNull', offset: at } : { tag: 'JsonBoolean', offset: at, value: literal === 'true' });
        at = end; finish(); break;
      }
    }
  }
}

export function encodeString(value: string): string {
  return JSON.stringify(utf8Decoder.decode(utf8Bytes(value)));
}

export function encode(events: readonly JsonEvent[]): JsonEncodeResult {
  type State = 'value' | 'objectFirst' | 'objectNext' | 'objectValue' | 'arrayFirst' | 'arrayNext' | 'done';
  let state: State = 'value';
  const stack: State[] = ['done'];
  const output: string[] = [];
  let index = 0;
  const fail = (message: string): JsonEncodeResult => ({ tag: 'JsonEncodeError', eventIndex: index, message });
  while (true) {
    const event = events[index];
    if (state === 'done') return index === events.length ? { tag: 'JsonEncoded', text: output.join('') } : fail('unexpected event after complete JSON value');
    if (state === 'objectFirst' || state === 'objectNext') {
      if (!event) return fail('unterminated object event sequence');
      if (event.tag === 'JsonObjectEnd') { output.push('}'); state = stack.pop()!; index++; continue; }
      if (event.tag !== 'JsonKey') return fail('object expects a key or object end event');
      output.push((state === 'objectNext' ? ',' : '') + encodeString(event.value) + ':'); state = 'objectValue'; index++; continue;
    }
    const array = state === 'arrayFirst' || state === 'arrayNext';
    if (!event) return fail(array ? 'unterminated array event sequence' : state === 'objectValue' ? 'object key has no value event' : 'expected a JSON value event');
    if (array && event.tag === 'JsonArrayEnd') { output.push(']'); state = stack.pop()!; index++; continue; }
    const continuation: State = array ? 'arrayNext' : state === 'objectValue' ? 'objectNext' : stack.pop()!;
    const prefix = state === 'arrayNext' ? ',' : '';
    switch (event.tag) {
      case 'JsonObjectStart': output.push(prefix + '{'); stack.push(continuation); state = 'objectFirst'; break;
      case 'JsonArrayStart': output.push(prefix + '['); stack.push(continuation); state = 'arrayFirst'; break;
      case 'JsonString': output.push(prefix + encodeString(event.value)); state = continuation; break;
      case 'JsonNumber': {
        const bytes = utf8Bytes(event.lexeme);
        const token = numberToken(bytes, 0);
        if ('message' in token || token.next !== bytes.length) return fail('number event has an invalid JSON lexeme');
        output.push(prefix + event.lexeme); state = continuation; break;
      }
      case 'JsonBoolean': output.push(prefix + (event.value ? 'true' : 'false')); state = continuation; break;
      case 'JsonNull': output.push(prefix + 'null'); state = continuation; break;
      case 'JsonKey': return fail('unexpected object key event');
      case 'JsonObjectEnd': return fail('unexpected object end event');
      case 'JsonArrayEnd': return fail('unexpected array end event');
    }
    index++;
  }
}
