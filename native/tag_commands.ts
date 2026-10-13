import * as json from './native_json.ts';
import * as r from './tag_resolve.ts';
export type HostDocument = { tags: r.HostTags; active: string[] };
export function makeHostDocument(tags: r.HostTags, active: string[]): HostDocument { return { tags, active }; }
export type TagMutation = { changed: boolean; remove: string[]; add: string[] };
export function makeTagMutation(changed: boolean, remove: string[], add: string[]): TagMutation { return { changed, remove, add }; }
export type TagModuleLeaf = { _tag: "TagModuleParsed"; tag: string; module: string }
  | { _tag: "TagModuleRejected"; leaf: string };
export type ModuleLookup = { _tag: "ModuleFound"; value: r.ModuleTags }
  | { _tag: "ModuleMissing"; name: string };
export type TagIndexResult = { _tag: "TagIndexRendered"; text: string }
  | { _tag: "TagIndexRejected"; message: string };

export function stringJoin(values: string[], separator: string): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + ((index === 0) ? "" : separator) + values[index])];
    continue;
  }
}

export function spaces(amount: number): string {
  let remaining: number = amount;
  let result: string = "";
  while (true) {
    if ((remaining <= 0)) {
      return result;
    }
    [remaining, result] = [(remaining - 1), ("" + result + " ")];
    continue;
  }
}

export function padRight(value: string, width: number): string {
  return ("" + value + spaces((width - value.length)));
}

export function prefixValues(prefix: string, values: string[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, result] = [(index + 1), [...result, ("" + prefix + values[index])]];
    continue;
  }
}

export function findModule(modules: r.ModuleTags[], name: string): ModuleLookup {
  let index: number = 0;
  while (true) {
    if ((index >= modules.length)) {
      return { _tag: "ModuleMissing" as const, name: name };
    }
    const module: r.ModuleTags = modules[index];
    if ((name === module.name)) {
      return { _tag: "ModuleFound" as const, value: module };
    }
    index = (index + 1);
    continue;
  }
}

export function universeAddAll(universe: string[], values: string[]): string[] {
  let index: number = 0;
  let result: string[] = universe;
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, result] = [(index + 1), r.appendUnique(result, values[index])];
    continue;
  }
}

export function tagUniverse(modules: r.ModuleTags[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= modules.length)) {
      return result.slice().sort();
    }
    const module: r.ModuleTags = modules[index];
    [index, result] = [(index + 1), universeAddAll(universeAddAll(result, module.tags), module.optIn)];
    continue;
  }
}

export function tagMembershipCount(modules: r.ModuleTags[], tag: string, optIn: boolean): number {
  let index: number = 0;
  let total: number = 0;
  while (true) {
    if ((index >= modules.length)) {
      return total;
    }
    const module: r.ModuleTags = modules[index];
    const values: string[] = (optIn ? module.optIn : module.tags);
    [index, total] = [(index + 1), (total + (r.stringMember(values, tag) ? 1 : 0))];
    continue;
  }
}

export function taggedModuleCount(modules: r.ModuleTags[]): number {
  let index: number = 0;
  let total: number = 0;
  while (true) {
    if ((index >= modules.length)) {
      return total;
    }
    const module: r.ModuleTags = modules[index];
    [index, total] = [(index + 1), (total + (((module.tags.length > 0) || (module.optIn.length > 0)) ? 1 : 0))];
    continue;
  }
}

export function renderTagList(modules: r.ModuleTags[]): string {
  const tags: string[] = tagUniverse(modules);
  const heading: string = ((tags.length === 0) ? "No tags found. Add '<module> is tagged <tag>' facts to modules' default.gal.\n" : ("" + "Tags (" + tags.length + "):\n"));
  const body: string = (() => {
    let index: number = 0;
    let result: string = heading;
    while (true) {
      if ((index >= tags.length)) {
        return result;
      }
      const tag: string = tags[index];
      const defaults: number = tagMembershipCount(modules, tag, false);
      const optIns: number = tagMembershipCount(modules, tag, true);
      [index, result] = [(index + 1), ("" + result + "  " + padRight(tag, 18) + "  (" + defaults + " default" + ((optIns === 0) ? "" : ("" + ", " + optIns + " opt-in")) + ")\n")];
      continue;
    }
  })();
  return ("" + body + "\nCoverage: " + taggedModuleCount(modules) + " / " + modules.length + " modules carry at least one tag.\n");
}

export function renderTagShow(module: r.ModuleTags): string {
  const name: string = module.name;
  const defaults: string[] = module.tags;
  const optIns: string[] = module.optIn;
  return ("" + "module: " + name + "\n" + ":tags         " + ((defaults.length === 0) ? ("" + "(none \u2014 add '" + name + " is tagged <tag>' to modules/" + name + "/default.gal)") : stringJoin(defaults, ", ")) + "\n:tags-opt-in  " + ((optIns.length === 0) ? "(none)" : stringJoin(optIns, ", ")) + "\n");
}

export function modulesWithTag(modules: r.ModuleTags[], tag: string): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= modules.length)) {
      return result.slice().sort();
    }
    const module: r.ModuleTags = modules[index];
    [index, result] = [(index + 1), ((r.stringMember(module.tags, tag) || r.stringMember(module.optIn, tag)) ? [...result, module.name] : result)];
    continue;
  }
}

export function moduleTagKind(module: r.ModuleTags, tag: string): string {
  if (r.stringMember(module.tags, tag)) {
    return "default";
  }
  return "opt-in";
}

export function renderTagFilter(modules: r.ModuleTags[], tag: string): string {
  const names: string[] = modulesWithTag(modules, tag);
  if ((names.length === 0)) {
    return ("" + "no modules tagged '" + tag + "'\n");
  }
  let index: number = 0;
  let result: string = ("" + "modules tagged '" + tag + "' (" + names.length + "):\n");
  while (true) {
    if ((index >= names.length)) {
      return result;
    }
    const name: string = names[index];
    const matched104 = findModule(modules, name);
    switch (matched104._tag) {
      case "ModuleMissing": {
        const missing = matched104.name;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "ModuleFound": {
        const module = matched104.value;
        [index, result] = [(index + 1), ("" + result + "  " + name + "  (" + moduleTagKind(module, tag) + ")\n")];
        continue;
      }
    }
  }
}

export function appendJsonStrings(events: json.JsonEvent[], values: string[]): json.JsonEvent[] {
  let index: number = 0;
  let result: json.JsonEvent[] = events;
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, result] = [(index + 1), [...result, { tag: "JsonString" as const, offset: 0, value: values[index] }]];
    continue;
  }
}

export function moduleIndexEvents(module: r.ModuleTags): json.JsonEvent[] {
  const withName: json.JsonEvent[] = [{ tag: "JsonObjectStart" as const, offset: 0 }, { tag: "JsonKey" as const, offset: 0, value: "name" }, { tag: "JsonString" as const, offset: 0, value: module.name }, { tag: "JsonKey" as const, offset: 0, value: "tags" }, { tag: "JsonArrayStart" as const, offset: 0 }];
  const withTags: json.JsonEvent[] = appendJsonStrings(withName, module.tags);
  const withOptInKey: json.JsonEvent[] = [...withTags, ...[{ tag: "JsonArrayEnd" as const, offset: 0 }, { tag: "JsonKey" as const, offset: 0, value: "tags_opt_in" }, { tag: "JsonArrayStart" as const, offset: 0 }]];
  const withOptIns: json.JsonEvent[] = appendJsonStrings(withOptInKey, module.optIn);
  return [...withOptIns, ...[{ tag: "JsonArrayEnd" as const, offset: 0 }, { tag: "JsonObjectEnd" as const, offset: 0 }]];
}

export function renderTagIndex(modules: r.ModuleTags[]): TagIndexResult {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= modules.length)) {
      return { _tag: "TagIndexRendered" as const, text: result };
    }
    const module: r.ModuleTags = modules[index];
    const matched107 = json.encode(moduleIndexEvents(module));
    switch (matched107.tag) {
      case "JsonEncodeError": {
        const eventIndex = matched107.eventIndex;
        const message = matched107.message;
        return { _tag: "TagIndexRejected" as const, message: ("" + "cannot encode module '" + module.name + "': " + message) };
      }
      case "JsonEncoded": {
        const text = matched107.text;
        [index, result] = [(index + 1), ("" + result + text + "\n")];
        continue;
      }
    }
  }
}

export function hostFactsPath(host: string): string {
  return ("" + "hosts/" + host + "/_generated-enables.gal");
}

export function enablesFact(host: string, tag: string): string {
  return ("" + host + " enables " + tag);
}

export function addsFact(host: string, module: string, tag: string): string {
  return ("" + host + " adds " + module + " to " + tag);
}

export function dropsFact(host: string, module: string, tag: string): string {
  return ("" + host + " drops " + module + " from " + tag);
}

export function disablesFact(host: string, module: string): string {
  return ("" + host + " disables " + module);
}

export function enabledEntryString(entry: r.EnabledTag): string {
  const edits: string[] = [...prefixValues("+", entry.pluses), ...prefixValues("-", entry.minuses)];
  if ((edits.length === 0)) {
    return entry.tag;
  }
  return ("" + "[" + entry.tag + " " + stringJoin(edits, " ") + "]");
}

export function renderEnabledStatus(enabled: r.EnabledTag[]): string {
  if ((enabled.length === 0)) {
    return "  (none)\n";
  }
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= enabled.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + "  " + enabledEntryString(enabled[index]) + "\n")];
    continue;
  }
}

export function renderDisabledStatus(disabled: string[]): string {
  if ((disabled.length === 0)) {
    return "  (none)\n";
  }
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= disabled.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + "  " + disabled[index] + "\n")];
    continue;
  }
}

export function validationErrorHint(error: r.ValidationError): string {
  const matched110 = error;
  switch (matched110._tag) {
    case "UnknownPlatform": {
      const host = matched110.host;
      const platform = matched110.platform;
      const hint = matched110.hint;
      return hint;
    }
    case "UnknownTag": {
      const host = matched110.host;
      const tag = matched110.tag;
      const hint = matched110.hint;
      return hint;
    }
    case "OptInMismatch": {
      const host = matched110.host;
      const tag = matched110.tag;
      const module = matched110.module;
      const hint = matched110.hint;
      return hint;
    }
    case "UnknownDisabled": {
      const host = matched110.host;
      const module = matched110.module;
      const hint = matched110.hint;
      return hint;
    }
  }
}

export function renderResolutionErrors(errors: r.ValidationError[]): string {
  if ((errors.length === 0)) {
    return "";
  }
  let index: number = 0;
  let result: string = ("" + "Resolution errors (" + errors.length + "):\n");
  while (true) {
    if ((index >= errors.length)) {
      return ("" + result + "\n");
    }
    [index, result] = [(index + 1), ("" + result + "  " + validationErrorHint(errors[index]) + "\n")];
    continue;
  }
}

export function renderActiveStatus(active: string[]): string {
  const heading: string = ("" + "Resolved active modules (" + active.length + "):\n");
  if ((active.length === 0)) {
    return ("" + heading + "  (none)\n");
  }
  let index: number = 0;
  let result: string = heading;
  while (true) {
    if ((index >= active.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + "  " + active[index] + "\n")];
    continue;
  }
}

export function renderTagStatus(modules: r.ModuleTags[], document: HostDocument): string {
  const tags: r.HostTags = document.tags;
  const enabled: r.EnabledTag[] = tags.enabled;
  const disabled: string[] = tags.disabled;
  const resolution: r.Resolution = r.resolve(modules, tags);
  return ("" + "Host: " + tags.host + "\n" + "Platform: " + tags.platform + "\n" + "Source: " + hostFactsPath(tags.host) + "\n\n" + ":enabled (" + enabled.length + "):\n" + renderEnabledStatus(enabled) + "\n:disabled (" + disabled.length + "):\n" + renderDisabledStatus(disabled) + "\n" + renderResolutionErrors(resolution.errors) + renderActiveStatus(document.active));
}

export function findEnabled(enabled: r.EnabledTag[], tag: string): r.EnabledTag | null {
  let index: number = 0;
  while (true) {
    if ((index >= enabled.length)) {
      return null;
    }
    if ((tag === enabled[index].tag)) {
      return enabled[index];
    }
    index = (index + 1);
    continue;
  }
}

export function unchanged(): TagMutation {
  return makeTagMutation(false, [], []);
}

export function enableTag(document: HostDocument, tag: string): TagMutation {
  const tags: r.HostTags = document.tags;
  if ((findEnabled(tags.enabled, tag) !== null)) {
    return unchanged();
  }
  return makeTagMutation(true, [], [enablesFact(tags.host, tag)]);
}

export function editFacts(host: string, entry: r.EnabledTag): string[] {
  const tag: string = entry.tag;
  return [...(() => {
    let index: number = 0;
    let result: string[] = [];
    while (true) {
      if ((index >= entry.pluses.length)) {
        return result;
      }
      [index, result] = [(index + 1), [...result, addsFact(host, entry.pluses[index], tag)]];
      continue;
    }
  })(), ...(() => {
    let index: number = 0;
    let result: string[] = [];
    while (true) {
      if ((index >= entry.minuses.length)) {
        return result;
      }
      [index, result] = [(index + 1), [...result, dropsFact(host, entry.minuses[index], tag)]];
      continue;
    }
  })()];
}

export function disableTag(document: HostDocument, tag: string): TagMutation {
  const tags: r.HostTags = document.tags;
  const host: string = tags.host;
  const found: r.EnabledTag | null = findEnabled(tags.enabled, tag);
  if ((found === null)) {
    return unchanged();
  }
  const entry: r.EnabledTag = found;
  return makeTagMutation(true, [...[enablesFact(host, tag)], ...editFacts(host, entry)], []);
}

export function addTagEdit(document: HostDocument, tag: string, module: string, plus: boolean): TagMutation {
  const tags: r.HostTags = document.tags;
  const host: string = tags.host;
  const edit: string = (plus ? addsFact(host, module, tag) : dropsFact(host, module, tag));
  const found: r.EnabledTag | null = findEnabled(tags.enabled, tag);
  if ((found === null)) {
    return makeTagMutation(true, [], [enablesFact(host, tag), edit]);
  }
  const entry: r.EnabledTag = found;
  if (r.stringMember((plus ? entry.pluses : entry.minuses), module)) {
    return unchanged();
  }
  return makeTagMutation(true, [], [edit]);
}

export function disableModule(document: HostDocument, module: string): TagMutation {
  const tags: r.HostTags = document.tags;
  if (r.stringMember(tags.disabled, module)) {
    return unchanged();
  }
  return makeTagMutation(true, [], [disablesFact(tags.host, module)]);
}

export function enableModule(document: HostDocument, module: string): TagMutation {
  const tags: r.HostTags = document.tags;
  if (r.stringMember(tags.disabled, module)) {
    return makeTagMutation(true, [disablesFact(tags.host, module)], []);
  }
  return unchanged();
}

export function splitTagModule(leaf: string): TagModuleLeaf {
  let index: number = 0;
  while (true) {
    if ((index >= leaf.length)) {
      return { _tag: "TagModuleRejected" as const, leaf: leaf };
    }
    if (("+" === leaf.slice(index, (index + 1)))) {
      if (((index > 0) && ((index + 1) < leaf.length))) {
        return { _tag: "TagModuleParsed" as const, tag: leaf.slice(0, index), module: leaf.slice((index + 1), leaf.length) };
      }
      return { _tag: "TagModuleRejected" as const, leaf: leaf };
    }
    index = (index + 1);
    continue;
  }
}
