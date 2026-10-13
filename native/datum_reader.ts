export type ReaderEvent = { kind: string; value: string; literal: string; offset: number; depth: number };
export function makeReaderEvent(kind: string, value: string, literal: string, offset: number, depth: number): ReaderEvent { return { kind, value, literal, offset, depth }; }
export type DatumRead = { events: ReaderEvent[]; error: string | null; errorOffset: number };
export function makeDatumRead(events: ReaderEvent[], error: string | null, errorOffset: number): DatumRead { return { events, error, errorOffset }; }
type TokenScan = { nextOffset: number; value: string; literal: string; error: string | null };
function makeTokenScan(nextOffset: number, value: string, literal: string, error: string | null): TokenScan { return { nextOffset, value, literal, error }; }

function characterAt(source: string, offset: number): string {
  return source.slice(offset, (offset + 1));
}

function whitespace(character: string): boolean {
  return ((character === " ") || (character === "\t") || (character === "\r") || (character === "\n") || (character === ","));
}

function delimiter(character: string): boolean {
  return (whitespace(character) || (character === "(") || (character === ")") || (character === "[") || (character === "]") || (character === "{") || (character === "}") || (character === "\"") || (character === ";") || (character === "^") || (character === "`") || (character === "~") || (character === "\\"));
}

function escapeCharacter(character: string): string | null {
  if ((character === "\"")) {
    return "\"";
  }else if ((character === "\\")) {
    return "\\";
  }else if ((character === "n")) {
    return "\n";
  }else if ((character === "r")) {
    return "\r";
  }else if ((character === "t")) {
    return "\t";
  }else if ((character === "b")) {
    return "\b";
  }else if ((character === "f")) {
    return "\f";
  }else {
    return null;
  }
}

function renderStringCharacter(character: string): string {
  if ((character === "\"")) {
    return "\\\"";
  }else if ((character === "\\")) {
    return "\\\\";
  }else if ((character === "\n")) {
    return "\\n";
  }else if ((character === "\r")) {
    return "\\r";
  }else if ((character === "\t")) {
    return "\\t";
  }else if ((character === "\b")) {
    return "\\b";
  }else if ((character === "\f")) {
    return "\\f";
  }else {
    return character;
  }
}

function renderStringLiteral(value: string): string {
  let offset: number = 0;
  let rendered: string = "\"";
  while (true) {
    if ((offset === value.length)) {
      return ("" + rendered + "\"");
    }
    [offset, rendered] = [(offset + 1), ("" + rendered + renderStringCharacter(characterAt(value, offset)))];
    continue;
  }
}

function scanString(source: string, start: number): TokenScan {
  let offset: number = (start + 1);
  let value: string = "";
  while (true) {
    if ((offset === source.length)) {
      return makeTokenScan(offset, value, "", "unterminated string literal");
    }
    const character: string = characterAt(source, offset);
    if ((character === "\"")) {
      return makeTokenScan((offset + 1), value, renderStringLiteral(value), null);
    }else if ((character === "\\")) {
      if (((offset + 1) === source.length)) {
        return makeTokenScan((offset + 1), value, "", "unterminated string escape");
      }
      const escaped: string = characterAt(source, (offset + 1));
      const decoded: string | null = escapeCharacter(escaped);
      if ((decoded === null)) {
        return makeTokenScan((offset + 2), value, "", ("" + "unsupported string escape: \\" + escaped));
      }
      [offset, value] = [(offset + 2), ("" + value + decoded)];
      continue;
    }else {
      [offset, value] = [(offset + 1), ("" + value + character)];
      continue;
    }
  }
}

function scanAtom(source: string, start: number): TokenScan {
  let offset: number = start;
  while (true) {
    if (((offset === source.length) || delimiter(characterAt(source, offset)))) {
      const value: string = source.slice(start, offset);
      return makeTokenScan(offset, value, value, null);
    }
    offset = (offset + 1);
    continue;
  }
}

function atomKind(value: string): string {
  if (((value.length > 0) && (value.slice(0, 1) === ":"))) {
    return "keyword";
  }else if (((value === "true") || (value === "false"))) {
    return "boolean";
  }else if ((value === "nil")) {
    return "nil";
  }else {
    return "symbol";
  }
}

function openKind(character: string): string {
  if ((character === "(")) {
    return "list/open";
  }else if ((character === "[")) {
    return "vector/open";
  }else if ((character === "{")) {
    return "map/open";
  }else {
    return "set/open";
  }
}

function closeKind(opened: string): string {
  if ((opened === "list/open")) {
    return "list/close";
  }else if ((opened === "vector/open")) {
    return "vector/close";
  }else if ((opened === "map/open")) {
    return "map/close";
  }else {
    return "set/close";
  }
}

function matchingClose(opened: string, character: string): boolean {
  return (((opened === "list/open") && (character === ")")) || ((opened === "vector/open") && (character === "]")) || ((opened === "map/open") && (character === "}")) || ((opened === "set/open") && (character === "}")));
}

function opening(character: string): boolean {
  return ((character === "(") || (character === "[") || (character === "{"));
}

function closing(character: string): boolean {
  return ((character === ")") || (character === "]") || (character === "}"));
}

function prefixKind(source: string, offset: number): string | null {
  const character: string = characterAt(source, offset);
  if ((character === "'")) {
    return "quote";
  }else if ((character === "`")) {
    return "quasiquote";
  }else if ((character === "^")) {
    return "metadata";
  }else if ((character === "~")) {
    if ((((offset + 1) < source.length) && (characterAt(source, (offset + 1)) === "@"))) {
      return "unquote_splicing";
    }
    return "unquote";
  }else {
    return null;
  }
}

function prefixWidth(kind: string): number {
  if ((kind === "unquote_splicing")) {
    return 2;
  }
  return 1;
}

function success(events: ReaderEvent[]): DatumRead {
  return makeDatumRead(events, null, -1);
}

function failure(events: ReaderEvent[], message: string, offset: number): DatumRead {
  return makeDatumRead(events, message, offset);
}

export function readEvents(source: string): DatumRead {
  let offset: number = 0;
  let stack: string[] = [];
  let events: ReaderEvent[] = [];
  while (true) {
    if ((offset === source.length)) {
      if ((stack.length === 0)) {
        return success(events);
      }
      return failure(events, "unterminated data container", offset);
    }
    const character: string = characterAt(source, offset);
    const prefix: string | null = prefixKind(source, offset);
    if (whitespace(character)) {
      [offset, stack, events] = [(offset + 1), stack, events];
      continue;
    }else if ((character === ";")) {
      const nextOffset: number = (() => {
        let cursor: number = (offset + 1);
        while (true) {
          if (((cursor === source.length) || (characterAt(source, cursor) === "\n"))) {
            return cursor;
          }
          cursor = (cursor + 1);
          continue;
        }
      })();
      [offset, stack, events] = [nextOffset, stack, events];
      continue;
    }else if (((character === "#") && ((offset + 1) < source.length) && (characterAt(source, (offset + 1)) === "{"))) {
      const kind: string = "set/open";
      [offset, stack, events] = [(offset + 2), [...stack, kind], [...events, makeReaderEvent(kind, "", "#{", offset, stack.length)]];
      continue;
    }else if (opening(character)) {
      const kind: string = openKind(character);
      [offset, stack, events] = [(offset + 1), [...stack, kind], [...events, makeReaderEvent(kind, "", character, offset, stack.length)]];
      continue;
    }else if (closing(character)) {
      if ((stack.length === 0)) {
        return failure(events, "unexpected closing delimiter", offset);
      }
      const opened: string = stack.at(-1)!;
      if (matchingClose(opened, character)) {
        [offset, stack, events] = [(offset + 1), stack.slice(0, -1), [...events, makeReaderEvent(closeKind(opened), "", character, offset, (stack.length - 1))]];
        continue;
      }
      return failure(events, "mismatched closing delimiter", offset);
    }else if ((character === "\"")) {
      const scan: TokenScan = scanString(source, offset);
      const error: string | null = scan.error;
      if ((error !== null)) {
        return failure(events, error, offset);
      }
      [offset, stack, events] = [scan.nextOffset, stack, [...events, makeReaderEvent("string", scan.value, scan.literal, offset, stack.length)]];
      continue;
    }else if ((prefix !== null)) {
      const width: number = prefixWidth(prefix);
      const literal: string = source.slice(offset, (offset + width));
      [offset, stack, events] = [(offset + width), stack, [...events, makeReaderEvent(prefix, "", literal, offset, stack.length)]];
      continue;
    }else {
      const scan: TokenScan = scanAtom(source, offset);
      if ((scan.nextOffset === offset)) {
        return failure(events, "unsupported reader character", offset);
      }
      [offset, stack, events] = [scan.nextOffset, stack, [...events, makeReaderEvent(atomKind(scan.value), scan.value, scan.literal, offset, stack.length)]];
      continue;
    }
  }
}

export function readOk(result: DatumRead): boolean {
  return (result.error === null);
}

export function renderLiteral(kind: string, value: string): string {
  if ((kind === "string")) {
    return renderStringLiteral(value);
  }
  return value;
}
