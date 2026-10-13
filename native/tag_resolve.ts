export type OverrideValue = { path: string; literal: string };
export function makeOverrideValue(path: string, literal: string): OverrideValue { return { path, literal }; }
export type TaggedOverrides = { tag: string; values: OverrideValue[] };
export function makeTaggedOverrides(tag: string, values: OverrideValue[]): TaggedOverrides { return { tag, values }; }
export type ModuleTags = { name: string; tags: string[]; optIn: string[]; overrides: TaggedOverrides[] };
export function makeModuleTags(name: string, tags: string[], optIn: string[], overrides: TaggedOverrides[]): ModuleTags { return { name, tags, optIn, overrides }; }
export type EnabledTag = { tag: string; pluses: string[]; minuses: string[] };
export function makeEnabledTag(tag: string, pluses: string[], minuses: string[]): EnabledTag { return { tag, pluses, minuses }; }
export type HostTags = { host: string; enabled: EnabledTag[]; disabled: string[]; platform: string; restrictAllowed: boolean; allowed: string[] };
export function makeHostTags(host: string, enabled: EnabledTag[], disabled: string[], platform: string, restrictAllowed: boolean, allowed: string[]): HostTags { return { host, enabled, disabled, platform, restrictAllowed, allowed }; }
export type TagContribution = { tag: string; modules: string[] };
export function makeTagContribution(tag: string, modules: string[]): TagContribution { return { tag, modules }; }
export type ModuleOverrides = { module: string; values: OverrideValue[] };
export function makeModuleOverrides(module: string, values: OverrideValue[]): ModuleOverrides { return { module, values }; }
export type ValidationError = { _tag: "UnknownPlatform"; host: string; platform: string; hint: string }
  | { _tag: "UnknownTag"; host: string; tag: string; hint: string }
  | { _tag: "OptInMismatch"; host: string; tag: string; module: string; hint: string }
  | { _tag: "UnknownDisabled"; host: string; module: string; hint: string };
export type Resolution = { host: string; active: string[]; perTag: TagContribution[]; overrides: ModuleOverrides[]; errors: ValidationError[]; warnings: string[] };
export function makeResolution(host: string, active: string[], perTag: TagContribution[], overrides: ModuleOverrides[], errors: ValidationError[], warnings: string[]): Resolution { return { host, active, perTag, overrides, errors, warnings }; }
export type TagEdit = { _tag: "PlusEdit"; module: string }
  | { _tag: "MinusEdit"; module: string }
  | { _tag: "IgnoredEdit"; text: string };

export function stringMember(values: string[], candidate: string): boolean {
  let index: number = 0;
  while (true) {
    if ((index >= values.length)) {
      return false;
    }
    if ((values[index] === candidate)) {
      return true;
    }
    index = (index + 1);
    continue;
  }
}

export function appendUnique(values: string[], candidate: string): string[] {
  if (stringMember(values, candidate)) {
    return values;
  }
  return [...values, candidate];
}

export function unionStrings(left: string[], right: string[]): string[] {
  let index: number = 0;
  let result: string[] = left;
  while (true) {
    if ((index >= right.length)) {
      return result;
    }
    [index, result] = [(index + 1), appendUnique(result, right[index])];
    continue;
  }
}

export function removeStrings(values: string[], removed: string[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    const value: string = values[index];
    [index, result] = [(index + 1), (stringMember(removed, value) ? result : [...result, value])];
    continue;
  }
}

export function allowedModule(host: HostTags, module: string): boolean {
  return ((!host.restrictAllowed) || stringMember(host.allowed, module));
}

export function modulesDeclaringDefault(modules: ModuleTags[], tag: string): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    const module: ModuleTags = modules[index];
    [index, result] = [(index + 1), (stringMember(module.tags, tag) ? [...result, module.name] : result)];
    continue;
  }
}

export function modulesDeclaringOptIn(modules: ModuleTags[], tag: string): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    const module: ModuleTags = modules[index];
    [index, result] = [(index + 1), (stringMember(module.optIn, tag) ? [...result, module.name] : result)];
    continue;
  }
}

export function moduleKnown(modules: ModuleTags[], name: string): boolean {
  let index: number = 0;
  while (true) {
    if ((index >= modules.length)) {
      return false;
    }
    if ((modules[index].name === name)) {
      return true;
    }
    index = (index + 1);
    continue;
  }
}

export function parseTagEdit(text: string): TagEdit {
  if ((text.length === 0)) {
    return { _tag: "IgnoredEdit" as const, text: text };
  }
  const prefix: string = text.slice(0, 1);
  const module: string = text.slice(1);
  if ((prefix === "+")) {
    return { _tag: "PlusEdit" as const, module: module };
  }else if ((prefix === "-")) {
    return { _tag: "MinusEdit" as const, module: module };
  }else {
    return { _tag: "IgnoredEdit" as const, text: text };
  }
}

export function enabledTagFromEditTexts(tag: string, edits: string[]): EnabledTag {
  let index: number = 0;
  let pluses: string[] = [];
  let minuses: string[] = [];
  while (true) {
    if ((index >= edits.length)) {
      return makeEnabledTag(tag, pluses, minuses);
    }
    const matched8 = parseTagEdit(edits[index]);
    switch (matched8._tag) {
      case "PlusEdit": {
        const module = matched8.module;
        [index, pluses, minuses] = [(index + 1), [...pluses, module], minuses];
        continue;
      }
      case "MinusEdit": {
        const module = matched8.module;
        [index, pluses, minuses] = [(index + 1), pluses, [...minuses, module]];
        continue;
      }
      case "IgnoredEdit": {
        const text = matched8.text;
        [index, pluses, minuses] = [(index + 1), pluses, minuses];
        continue;
      }
    }
  }
}

export function filterAllowed(host: HostTags, modules: string[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    const module: string = modules[index];
    [index, result] = [(index + 1), (allowedModule(host, module) ? [...result, module] : result)];
    continue;
  }
}

export function validPluses(host: HostTags, pluses: string[], optIns: string[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= pluses.length)) {
      return result;
    }
    const module: string = pluses[index];
    [index, result] = [(index + 1), ((stringMember(optIns, module) && allowedModule(host, module)) ? [...result, module] : result)];
    continue;
  }
}

export function putContribution(contributions: TagContribution[], replacement: TagContribution): TagContribution[] {
  let index: number = 0;
  let found: boolean = false;
  let result: TagContribution[] = [];
  while (true) {
    if ((index >= contributions.length)) {
      if (found) {
        return result;
      }
      return [...result, replacement];
    }
    const current: TagContribution = contributions[index];
    if ((current.tag === replacement.tag)) {
      [index, found, result] = [(index + 1), true, [...result, replacement]];
      continue;
    }
    [index, found, result] = [(index + 1), found, [...result, current]];
    continue;
  }
}

export function appendModuleOverrides(overrides: ModuleOverrides[], module: string, values: OverrideValue[]): ModuleOverrides[] {
  let index: number = 0;
  let found: boolean = false;
  let result: ModuleOverrides[] = [];
  while (true) {
    if ((index >= overrides.length)) {
      if (found) {
        return result;
      }
      return [...result, makeModuleOverrides(module, values)];
    }
    const current: ModuleOverrides = overrides[index];
    if ((current.module === module)) {
      [index, found, result] = [(index + 1), true, [...result, makeModuleOverrides(module, [...values, ...current.values])]];
      continue;
    }
    [index, found, result] = [(index + 1), found, [...result, current]];
    continue;
  }
}

export function taggedOverrideValues(module: ModuleTags, tag: string): OverrideValue[] {
  let index: number = 0;
  while (true) {
    if ((index >= module.overrides.length)) {
      return [];
    }
    const entry: TaggedOverrides = module.overrides[index];
    if ((entry.tag === tag)) {
      return entry.values;
    }
    index = (index + 1);
    continue;
  }
}

export function collectDefaultOverrides(modules: ModuleTags[], tag: string, fromDefaults: string[], overrides: ModuleOverrides[]): ModuleOverrides[] {
  let index: number = 0;
  let result: ModuleOverrides[] = overrides;
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    const module: ModuleTags = modules[index];
    const name: string = module.name;
    const values: OverrideValue[] = taggedOverrideValues(module, tag);
    [index, result] = [(index + 1), ((stringMember(fromDefaults, name) && (values.length > 0)) ? appendModuleOverrides(result, name, values) : result)];
    continue;
  }
}

export function tagErrors(host: HostTags, tag: string, known: boolean, pluses: string[], optIns: string[]): ValidationError[] {
  const unknownErrors: ValidationError[] = (known ? [] : [{ _tag: "UnknownTag" as const, host: host.host, tag: tag, hint: ("" + "host '" + host.host + "' enables tag '" + tag + "' but no module declares it") }]);
  let index: number = 0;
  let result: ValidationError[] = unknownErrors;
  while (true) {
    if ((index >= pluses.length)) {
      return result;
    }
    const module: string = pluses[index];
    [index, result] = [(index + 1), (stringMember(optIns, module) ? result : [...result, { _tag: "OptInMismatch" as const, host: host.host, tag: tag, module: module, hint: ("" + "host '" + host.host + "' tag '" + tag + "': +" + module + " but module '" + module + "' does not list tag '" + tag + "' in :tags-opt-in") }])];
    continue;
  }
}

export function tagWarnings(host: HostTags, tag: string, minuses: string[], defaults: string[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= minuses.length)) {
      return result;
    }
    const module: string = minuses[index];
    [index, result] = [(index + 1), (stringMember(defaults, module) ? result : [...result, ("" + "host '" + host.host + "' tag '" + tag + "': -" + module + " but " + module + " is not in this tag's default set")])];
    continue;
  }
}

export function disabledErrors(modules: ModuleTags[], host: HostTags): ValidationError[] {
  let index: number = 0;
  let result: ValidationError[] = [];
  while (true) {
    if ((index >= host.disabled.length)) {
      return result;
    }
    const module: string = host.disabled[index];
    [index, result] = [(index + 1), (moduleKnown(modules, module) ? result : [...result, { _tag: "UnknownDisabled" as const, host: host.host, module: module, hint: ("" + "host '" + host.host + "' :disabled lists '" + module + "' but no such module exists") }])];
    continue;
  }
}

export function removeDisabledOverrides(overrides: ModuleOverrides[], disabled: string[]): ModuleOverrides[] {
  let index: number = 0;
  let result: ModuleOverrides[] = [];
  while (true) {
    if ((index >= overrides.length)) {
      return result;
    }
    const entry: ModuleOverrides = overrides[index];
    [index, result] = [(index + 1), (stringMember(disabled, entry.module) ? result : [...result, entry])];
    continue;
  }
}

export function resolve(modules: ModuleTags[], host: HostTags): Resolution {
  const platformErrors: ValidationError[] = (((host.platform === "linux") || (host.platform === "darwin")) ? [] : [{ _tag: "UnknownPlatform" as const, host: host.host, platform: host.platform, hint: ("" + "host '" + host.host + "' declares unsupported platform '" + host.platform + "'") }]);
  let index: number = 0;
  let active: string[] = [];
  let perTag: TagContribution[] = [];
  let overrides: ModuleOverrides[] = [];
  let errors: ValidationError[] = platformErrors;
  let warnings: string[] = [];
  while (true) {
    if ((index >= host.enabled.length)) {
      const withoutDisabled: string[] = removeStrings(active, host.disabled);
      return makeResolution(host.host, withoutDisabled.slice().sort(), perTag, removeDisabledOverrides(overrides, host.disabled), [...errors, ...disabledErrors(modules, host)], warnings);
    }
    const enabled: EnabledTag = host.enabled[index];
    const tag: string = enabled.tag;
    const defaults: string[] = modulesDeclaringDefault(modules, tag);
    const optIns: string[] = modulesDeclaringOptIn(modules, tag);
    const fromDefaults: string[] = filterAllowed(host, removeStrings(defaults, enabled.minuses));
    const fromPluses: string[] = validPluses(host, enabled.pluses, optIns);
    const contribution: string[] = unionStrings(fromDefaults, fromPluses).slice().sort();
    [index, active, perTag, overrides, errors, warnings] = [(index + 1), unionStrings(active, contribution), putContribution(perTag, makeTagContribution(tag, contribution)), collectDefaultOverrides(modules, tag, fromDefaults, overrides), [...errors, ...tagErrors(host, tag, ((defaults.length > 0) || (optIns.length > 0)), enabled.pluses, optIns)], [...warnings, ...tagWarnings(host, tag, enabled.minuses, defaults)]];
    continue;
  }
}

export function contributionFor(resolution: Resolution, tag: string): string[] {
  let index: number = 0;
  while (true) {
    if ((index >= resolution.perTag.length)) {
      return [];
    }
    const entry: TagContribution = resolution.perTag[index];
    if ((entry.tag === tag)) {
      return entry.modules;
    }
    index = (index + 1);
    continue;
  }
}

export function overridesFor(resolution: Resolution, module: string): OverrideValue[] {
  let index: number = 0;
  while (true) {
    if ((index >= resolution.overrides.length)) {
      return [];
    }
    const entry: ModuleOverrides = resolution.overrides[index];
    if ((entry.module === module)) {
      return entry.values;
    }
    index = (index + 1);
    continue;
  }
}

export function validationErrorKind(error: ValidationError): string {
  const matched22 = error;
  switch (matched22._tag) {
    case "UnknownPlatform": {
      const host = matched22.host;
      const platform = matched22.platform;
      const hint = matched22.hint;
      return "unknown-platform";
    }
    case "UnknownTag": {
      const host = matched22.host;
      const tag = matched22.tag;
      const hint = matched22.hint;
      return "unknown-tag";
    }
    case "OptInMismatch": {
      const host = matched22.host;
      const tag = matched22.tag;
      const module = matched22.module;
      const hint = matched22.hint;
      return "opt-in-mismatch";
    }
    case "UnknownDisabled": {
      const host = matched22.host;
      const module = matched22.module;
      const hint = matched22.hint;
      return "unknown-disabled";
    }
  }
}

export function validationErrorTag(error: ValidationError): string {
  const matched23 = error;
  switch (matched23._tag) {
    case "UnknownPlatform": {
      const host = matched23.host;
      const platform = matched23.platform;
      const hint = matched23.hint;
      return "";
    }
    case "UnknownTag": {
      const host = matched23.host;
      const tag = matched23.tag;
      const hint = matched23.hint;
      return tag;
    }
    case "OptInMismatch": {
      const host = matched23.host;
      const tag = matched23.tag;
      const module = matched23.module;
      const hint = matched23.hint;
      return tag;
    }
    case "UnknownDisabled": {
      const host = matched23.host;
      const module = matched23.module;
      const hint = matched23.hint;
      return "";
    }
  }
}

export function validationErrorModule(error: ValidationError): string {
  const matched24 = error;
  switch (matched24._tag) {
    case "UnknownPlatform": {
      const host = matched24.host;
      const platform = matched24.platform;
      const hint = matched24.hint;
      return "";
    }
    case "UnknownTag": {
      const host = matched24.host;
      const tag = matched24.tag;
      const hint = matched24.hint;
      return "";
    }
    case "OptInMismatch": {
      const host = matched24.host;
      const tag = matched24.tag;
      const module = matched24.module;
      const hint = matched24.hint;
      return module;
    }
    case "UnknownDisabled": {
      const host = matched24.host;
      const module = matched24.module;
      const hint = matched24.hint;
      return module;
    }
  }
}
