import * as reader from './datum_reader.ts';
import * as json from './native_json.ts';
import * as r from './tag_resolve.ts';
export type ModuleSourceResult = { _tag: "ModuleSourceParsed"; value: r.ModuleTags }
  | { _tag: "ModuleSourceRejected"; message: string; offset: number };
export type DarwinAllowlistResult = { _tag: "DarwinAllowlistParsed"; modules: string[] }
  | { _tag: "DarwinAllowlistRejected"; message: string; offset: number };
export type SpanScan = { ok: boolean; found: boolean; start: number; message: string; offset: number };
export function makeSpanScan(ok: boolean, found: boolean, start: number, message: string, offset: number): SpanScan { return { ok, found, start, message, offset }; }
export type StringVectorScan = { ok: boolean; values: string[]; message: string; offset: number };
export function makeStringVectorScan(ok: boolean, values: string[], message: string, offset: number): StringVectorScan { return { ok, values, message, offset }; }
export type OverrideValuesScan = { ok: boolean; values: r.OverrideValue[]; message: string; offset: number };
export function makeOverrideValuesScan(ok: boolean, values: r.OverrideValue[], message: string, offset: number): OverrideValuesScan { return { ok, values, message, offset }; }
export type OverridesScan = { ok: boolean; values: r.TaggedOverrides[]; message: string; offset: number };
export function makeOverridesScan(ok: boolean, values: r.TaggedOverrides[], message: string, offset: number): OverridesScan { return { ok, values, message, offset }; }
export type StringAtomScan = { ok: boolean; value: string; message: string; offset: number };
export function makeStringAtomScan(ok: boolean, value: string, message: string, offset: number): StringAtomScan { return { ok, value, message, offset }; }

export function spanFound(start: number): SpanScan {
  return makeSpanScan(true, true, start, "", -1);
}

export function spanMissing(): SpanScan {
  return makeSpanScan(true, false, -1, "", -1);
}

export function spanRejected(message: string, offset: number): SpanScan {
  return makeSpanScan(false, false, -1, message, offset);
}

export function eventOffset(events: reader.ReaderEvent[], index: number): number {
  if (((index >= 0) && (index < events.length))) {
    return events[index].offset;
  }
  return -1;
}

export function openKind(kind: string): boolean {
  return ((kind === "list/open") || (kind === "vector/open") || (kind === "map/open") || (kind === "set/open"));
}

export function closeKind(kind: string): boolean {
  return ((kind === "list/close") || (kind === "vector/close") || (kind === "map/close") || (kind === "set/close"));
}

export function matchingCloseKind(opened: string, closed: string): boolean {
  return (((opened === "list/open") && (closed === "list/close")) || ((opened === "vector/open") && (closed === "vector/close")) || ((opened === "map/open") && (closed === "map/close")) || ((opened === "set/open") && (closed === "set/close")));
}

export function datumEnd(events: reader.ReaderEvent[], start: number): number {
  if (((start < 0) || (start >= events.length))) {
    return -1;
  }
  const opening: reader.ReaderEvent = events[start];
  const kind: string = opening.kind;
  if (closeKind(kind)) {
    return -1;
  }else if ((!openKind(kind))) {
    return (start + 1);
  }else {
    let index: number = (start + 1);
    while (true) {
      if ((index >= events.length)) {
        return -1;
      }
      const event: reader.ReaderEvent = events[index];
      if (((event.depth === opening.depth) && matchingCloseKind(kind, event.kind))) {
        return (index + 1);
      }
      index = (index + 1);
      continue;
    }
  }
}

export function containerChildCount(events: reader.ReaderEvent[], start: number): number {
  const end: number = datumEnd(events, start);
  if (((end < 0) || (!openKind(events[start].kind)))) {
    return -1;
  }
  let cursor: number = (start + 1);
  let total: number = 0;
  while (true) {
    if ((cursor === (end - 1))) {
      return total;
    }else if ((cursor > (end - 1))) {
      return -1;
    }else {
      const next: number = datumEnd(events, cursor);
      if (((next < 0) || (next > (end - 1)))) {
        return -1;
      }
      [cursor, total] = [next, (total + 1)];
      continue;
    }
  }
}

export function containerChildStart(events: reader.ReaderEvent[], start: number, wanted: number): number {
  const end: number = datumEnd(events, start);
  if (((wanted < 0) || (end < 0) || (!openKind(events[start].kind)))) {
    return -1;
  }
  let cursor: number = (start + 1);
  let index: number = 0;
  while (true) {
    if ((cursor === (end - 1))) {
      return -1;
    }else if ((cursor > (end - 1))) {
      return -1;
    }else if ((index === wanted)) {
      return cursor;
    }else {
      const next: number = datumEnd(events, cursor);
      if (((next < 0) || (next > (end - 1)))) {
        return -1;
      }
      [cursor, index] = [next, (index + 1)];
      continue;
    }
  }
}

export function symbolAt(events: reader.ReaderEvent[], index: number, value: string): boolean {
  return ((index >= 0) && (index < events.length) && ("symbol" === events[index].kind) && (value === events[index].value));
}

export function listHead(events: reader.ReaderEvent[], start: number, head: string): boolean {
  return ((start >= 0) && (start < events.length) && ("list/open" === events[start].kind) && symbolAt(events, containerChildStart(events, start, 0), head));
}

export function findTopLevelForm(events: reader.ReaderEvent[], head: string): SpanScan {
  let cursor: number = 0;
  let found: number = -1;
  while (true) {
    if ((cursor === events.length)) {
      if ((found < 0)) {
        return spanMissing();
      }
      return spanFound(found);
    }
    const next: number = datumEnd(events, cursor);
    if ((next < 0)) {
      return spanRejected("invalid top-level datum", eventOffset(events, cursor));
    }
    if (listHead(events, cursor, head)) {
      if ((found >= 0)) {
        return spanRejected(("" + "duplicate top-level " + head + " form"), eventOffset(events, cursor));
      }
      [cursor, found] = [next, cursor];
      continue;
    }
    [cursor, found] = [next, found];
    continue;
  }
}

export function unwrapModuleBody(events: reader.ReaderEvent[], start: number): SpanScan {
  let current: number = start;
  let wrappers: number = 0;
  while (true) {
    if (((current < 0) || (current >= events.length))) {
      return spanRejected("missing nix/module body", -1);
    }
    const kind: string = events[current].kind;
    if ((kind === "map/open")) {
      return spanFound(current);
    }else if ((listHead(events, current, "let") || listHead(events, current, "lib.mkIf"))) {
      if ((wrappers >= 4)) {
        return spanRejected("module body has too many wrappers", eventOffset(events, current));
      }else if ((3 !== containerChildCount(events, current))) {
        return spanRejected("module body wrapper requires three forms", eventOffset(events, current));
      }else if ((listHead(events, current, "let") && ("vector/open" !== events[containerChildStart(events, current, 1)].kind))) {
        return spanRejected("let wrapper requires a binding vector", eventOffset(events, current));
      }else {
        [current, wrappers] = [containerChildStart(events, current, 2), (wrappers + 1)];
        continue;
      }
    }else {
      return spanRejected("unsupported nix/module body", eventOffset(events, current));
    }
  }
}

export function mapField(events: reader.ReaderEvent[], start: number, field: string): SpanScan {
  if (((start < 0) || (start >= events.length) || ("map/open" !== events[start].kind))) {
    return spanRejected("expected map", eventOffset(events, start));
  }
  const end: number = datumEnd(events, start);
  let cursor: number = (start + 1);
  let found: number = -1;
  while (true) {
    if ((cursor === (end - 1))) {
      if ((found < 0)) {
        return spanMissing();
      }
      return spanFound(found);
    }else if ((cursor > (end - 1))) {
      return spanRejected("malformed map", eventOffset(events, start));
    }else {
      const key: reader.ReaderEvent = events[cursor];
      const keyEnd: number = datumEnd(events, cursor);
      if ((((cursor + 1) !== keyEnd) || ("keyword" !== key.kind))) {
        return spanRejected("map key must be a keyword", key.offset);
      }else if ((keyEnd >= (end - 1))) {
        return spanRejected("map key is missing a value", key.offset);
      }else {
        const valueStart: number = keyEnd;
        const valueEnd: number = datumEnd(events, valueStart);
        const matches: boolean = (field === key.value);
        if (((valueEnd < 0) || (valueEnd > (end - 1)))) {
          return spanRejected("malformed map value", eventOffset(events, valueStart));
        }else if ((matches && (found >= 0))) {
          return spanRejected(("" + "duplicate " + field + " field"), key.offset);
        }else {
          [cursor, found] = [valueEnd, (matches ? valueStart : found)];
          continue;
        }
      }
    }
  }
}

export function readSymbolVector(events: reader.ReaderEvent[], start: number, label: string): StringVectorScan {
  if (((start < 0) || (start >= events.length) || ("vector/open" !== events[start].kind))) {
    return makeStringVectorScan(false, [], ("" + label + " must be a vector"), eventOffset(events, start));
  }
  const end: number = datumEnd(events, start);
  let cursor: number = (start + 1);
  let values: string[] = [];
  while (true) {
    if ((cursor === (end - 1))) {
      return makeStringVectorScan(true, values, "", -1);
    }
    const event: reader.ReaderEvent = events[cursor];
    const next: number = datumEnd(events, cursor);
    if ((((cursor + 1) !== next) || ("symbol" !== event.kind))) {
      return makeStringVectorScan(false, [], ("" + label + " entries must be symbols"), event.offset);
    }
    [cursor, values] = [next, [...values, event.value]];
    continue;
  }
}

export function readSymbolField(events: reader.ReaderEvent[], field: SpanScan, fallback: string): StringAtomScan {
  if ((!field.ok)) {
    return makeStringAtomScan(false, "", field.message, field.offset);
  }
  if ((!field.found)) {
    return makeStringAtomScan(true, fallback, "", -1);
  }
  const start: number = field.start;
  const event: reader.ReaderEvent = events[start];
  if ((((start + 1) === datumEnd(events, start)) && ("symbol" === event.kind))) {
    return makeStringAtomScan(true, event.value, "", -1);
  }
  return makeStringAtomScan(false, "", "field must be a symbol", event.offset);
}

export function overridePathMember(values: r.OverrideValue[], path: string): boolean {
  let index: number = 0;
  while (true) {
    if ((index >= values.length)) {
      return false;
    }
    if ((path === values[index].path)) {
      return true;
    }
    index = (index + 1);
    continue;
  }
}

export function taggedOverrideMember(values: r.TaggedOverrides[], tag: string): boolean {
  let index: number = 0;
  while (true) {
    if ((index >= values.length)) {
      return false;
    }
    if ((tag === values[index].tag)) {
      return true;
    }
    index = (index + 1);
    continue;
  }
}

export function literalAtom(kind: string): boolean {
  return ((kind === "string") || (kind === "boolean") || (kind === "nil") || (kind === "symbol") || (kind === "keyword"));
}

export function readOverrideValues(events: reader.ReaderEvent[], start: number): OverrideValuesScan {
  if (((start < 0) || (start >= events.length) || ("map/open" !== events[start].kind))) {
    return makeOverrideValuesScan(false, [], "tag override value must be a map", eventOffset(events, start));
  }
  const end: number = datumEnd(events, start);
  let cursor: number = (start + 1);
  let values: r.OverrideValue[] = [];
  while (true) {
    if ((cursor === (end - 1))) {
      return makeOverrideValuesScan(true, values, "", -1);
    }
    const key: reader.ReaderEvent = events[cursor];
    const keyEnd: number = datumEnd(events, cursor);
    if ((((cursor + 1) !== keyEnd) || ("keyword" !== key.kind))) {
      return makeOverrideValuesScan(false, [], "tag override path must be a keyword", key.offset);
    }else if ((keyEnd >= (end - 1))) {
      return makeOverrideValuesScan(false, [], "tag override path is missing a literal", key.offset);
    }else {
      const valueStart: number = keyEnd;
      const valueEnd: number = datumEnd(events, valueStart);
      const value: reader.ReaderEvent = events[valueStart];
      const path: string = key.value.slice(1);
      if ((((valueStart + 1) !== valueEnd) || (!literalAtom(value.kind)))) {
        return makeOverrideValuesScan(false, [], "tag override literal must be atomic", value.offset);
      }else if (overridePathMember(values, path)) {
        return makeOverrideValuesScan(false, [], ("" + "duplicate tag override path: " + path), key.offset);
      }else {
        [cursor, values] = [valueEnd, [...values, r.makeOverrideValue(path, value.literal)]];
        continue;
      }
    }
  }
}

export function readOverridesMap(events: reader.ReaderEvent[], start: number): OverridesScan {
  if (((start < 0) || (start >= events.length) || ("map/open" !== events[start].kind))) {
    return makeOverridesScan(false, [], ":tag-overrides must be a map", eventOffset(events, start));
  }
  const end: number = datumEnd(events, start);
  let cursor: number = (start + 1);
  let values: r.TaggedOverrides[] = [];
  while (true) {
    if ((cursor === (end - 1))) {
      return makeOverridesScan(true, values, "", -1);
    }
    const key: reader.ReaderEvent = events[cursor];
    const keyEnd: number = datumEnd(events, cursor);
    if ((((cursor + 1) !== keyEnd) || ("symbol" !== key.kind))) {
      return makeOverridesScan(false, [], "tag override key must be a symbol", key.offset);
    }else if ((keyEnd >= (end - 1))) {
      return makeOverridesScan(false, [], "tag override key is missing a value map", key.offset);
    }else {
      const tag: string = key.value;
      const valueStart: number = keyEnd;
      const valueEnd: number = datumEnd(events, valueStart);
      const inner: OverrideValuesScan = readOverrideValues(events, valueStart);
      if (((valueEnd < 0) || (valueEnd > (end - 1)))) {
        return makeOverridesScan(false, [], "malformed tag override value", eventOffset(events, valueStart));
      }else if (taggedOverrideMember(values, tag)) {
        return makeOverridesScan(false, [], ("" + "duplicate tag override: " + tag), key.offset);
      }else if ((!inner.ok)) {
        return makeOverridesScan(false, [], inner.message, inner.offset);
      }else {
        [cursor, values] = [valueEnd, [...values, r.makeTaggedOverrides(tag, inner.values)]];
        continue;
      }
    }
  }
}

export function optionalSymbolVector(events: reader.ReaderEvent[], field: SpanScan, label: string): StringVectorScan {
  if ((!field.ok)) {
    return makeStringVectorScan(false, [], field.message, field.offset);
  }else if ((!field.found)) {
    return makeStringVectorScan(true, [], "", -1);
  }else {
    return readSymbolVector(events, field.start, label);
  }
}

export function optionalOverrides(events: reader.ReaderEvent[], field: SpanScan): OverridesScan {
  if ((!field.ok)) {
    return makeOverridesScan(false, [], field.message, field.offset);
  }else if ((!field.found)) {
    return makeOverridesScan(true, [], "", -1);
  }else {
    return readOverridesMap(events, field.start);
  }
}

export function moduleTagsFromSource(name: string, source: string): ModuleSourceResult {
  const read: reader.DatumRead = reader.readEvents(source);
  const readError: string | null = read.error;
  if ((readError !== null)) {
    return { _tag: "ModuleSourceRejected" as const, message: readError, offset: read.errorOffset };
  }
  const events: reader.ReaderEvent[] = read.events;
  const moduleForm: SpanScan = findTopLevelForm(events, "nix/module");
  if ((!moduleForm.ok)) {
    return { _tag: "ModuleSourceRejected" as const, message: moduleForm.message, offset: moduleForm.offset };
  }else if ((!moduleForm.found)) {
    return { _tag: "ModuleSourceParsed" as const, value: r.makeModuleTags(name, [], [], []) };
  }else if ((3 !== containerChildCount(events, moduleForm.start))) {
    return { _tag: "ModuleSourceRejected" as const, message: "nix/module requires parameters and one body", offset: eventOffset(events, moduleForm.start) };
  }else {
    const formStart: number = moduleForm.start;
    const parameters: number = containerChildStart(events, formStart, 1);
    const body: SpanScan = unwrapModuleBody(events, containerChildStart(events, formStart, 2));
    if (("vector/open" !== events[parameters].kind)) {
      return { _tag: "ModuleSourceRejected" as const, message: "nix/module parameters must be a vector", offset: eventOffset(events, parameters) };
    }else if ((!body.ok)) {
      return { _tag: "ModuleSourceRejected" as const, message: body.message, offset: body.offset };
    }else {
      const bodyStart: number = body.start;
      const tagsField: SpanScan = mapField(events, bodyStart, ":tags");
      const optInField: SpanScan = mapField(events, bodyStart, ":tags-opt-in");
      const overridesField: SpanScan = mapField(events, bodyStart, ":tag-overrides");
      const tags: StringVectorScan = optionalSymbolVector(events, tagsField, ":tags");
      const optIn: StringVectorScan = optionalSymbolVector(events, optInField, ":tags-opt-in");
      const overrides: OverridesScan = optionalOverrides(events, overridesField);
      if ((!tags.ok)) {
        return { _tag: "ModuleSourceRejected" as const, message: tags.message, offset: tags.offset };
      }else if ((!optIn.ok)) {
        return { _tag: "ModuleSourceRejected" as const, message: optIn.message, offset: optIn.offset };
      }else if ((!overrides.ok)) {
        return { _tag: "ModuleSourceRejected" as const, message: overrides.message, offset: overrides.offset };
      }else {
        return { _tag: "ModuleSourceParsed" as const, value: r.makeModuleTags(name, tags.values, optIn.values, overrides.values) };
      }
    }
  }
}

export function jsonEventOffset(event: json.JsonEvent): number {
  const matched36 = event;
  switch (matched36.tag) {
    case "JsonObjectStart": {
      const offset = matched36.offset;
      return offset;
    }
    case "JsonObjectEnd": {
      const offset = matched36.offset;
      return offset;
    }
    case "JsonArrayStart": {
      const offset = matched36.offset;
      return offset;
    }
    case "JsonArrayEnd": {
      const offset = matched36.offset;
      return offset;
    }
    case "JsonKey": {
      const offset = matched36.offset;
      const value = matched36.value;
      return offset;
    }
    case "JsonString": {
      const offset = matched36.offset;
      const value = matched36.value;
      return offset;
    }
    case "JsonNumber": {
      const offset = matched36.offset;
      const lexeme = matched36.lexeme;
      return offset;
    }
    case "JsonBoolean": {
      const offset = matched36.offset;
      const value = matched36.value;
      return offset;
    }
    case "JsonNull": {
      const offset = matched36.offset;
      return offset;
    }
  }
}

export function darwinAllowlistFromJson(source: string): DarwinAllowlistResult {
  const matched37 = json.decode(source);
  switch (matched37.tag) {
    case "JsonDecodeError": {
      const offset = matched37.offset;
      const message = matched37.message;
      return { _tag: "DarwinAllowlistRejected" as const, message: message, offset: offset };
    }
    case "JsonDecoded": {
      const events = matched37.events;
      if ((events.length === 0)) {
        return { _tag: "DarwinAllowlistRejected" as const, message: "expected a JSON array", offset: 0 };
      }
      const matched38 = events[0];
      switch (matched38.tag) {
        case "JsonArrayStart": {
          const offset = matched38.offset;
          let index: number = 1;
          let modules: string[] = [];
          while (true) {
            if ((index >= events.length)) {
              return { _tag: "DarwinAllowlistRejected" as const, message: "unterminated JSON array", offset: offset };
            }
            const event: json.JsonEvent = events[index];
            const matched40 = event;
            switch (matched40.tag) {
              case "JsonString": {
                const itemOffset = matched40.offset;
                const value = matched40.value;
                [index, modules] = [(index + 1), [...modules, value]];
                continue;
              }
              case "JsonArrayEnd": {
                const endOffset = matched40.offset;
                if (((index + 1) === events.length)) {
                  return { _tag: "DarwinAllowlistParsed" as const, modules: modules };
                }
                return { _tag: "DarwinAllowlistRejected" as const, message: "unexpected events after JSON array", offset: endOffset };
              }
              case "JsonObjectStart": {
                const badOffset = matched40.offset;
                return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist entries must be strings", offset: badOffset };
              }
              case "JsonObjectEnd": {
                const badOffset = matched40.offset;
                return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist entries must be strings", offset: badOffset };
              }
              case "JsonArrayStart": {
                const badOffset = matched40.offset;
                return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist entries must be strings", offset: badOffset };
              }
              case "JsonKey": {
                const badOffset = matched40.offset;
                const value = matched40.value;
                return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist entries must be strings", offset: badOffset };
              }
              case "JsonNumber": {
                const badOffset = matched40.offset;
                const lexeme = matched40.lexeme;
                return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist entries must be strings", offset: badOffset };
              }
              case "JsonBoolean": {
                const badOffset = matched40.offset;
                const value = matched40.value;
                return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist entries must be strings", offset: badOffset };
              }
              case "JsonNull": {
                const badOffset = matched40.offset;
                return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist entries must be strings", offset: badOffset };
              }
            }
          }
        }
        case "JsonObjectStart": {
          const badOffset = matched38.offset;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
        case "JsonObjectEnd": {
          const badOffset = matched38.offset;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
        case "JsonArrayEnd": {
          const badOffset = matched38.offset;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
        case "JsonKey": {
          const badOffset = matched38.offset;
          const value = matched38.value;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
        case "JsonString": {
          const badOffset = matched38.offset;
          const value = matched38.value;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
        case "JsonNumber": {
          const badOffset = matched38.offset;
          const lexeme = matched38.lexeme;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
        case "JsonBoolean": {
          const badOffset = matched38.offset;
          const value = matched38.value;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
        case "JsonNull": {
          const badOffset = matched38.offset;
          return { _tag: "DarwinAllowlistRejected" as const, message: "Darwin allowlist must be a JSON array", offset: badOffset };
        }
      }
    }
  }
}
