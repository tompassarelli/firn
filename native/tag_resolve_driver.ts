import * as r from './tag_resolve.ts';
export type TagResolveAction = { _tag: "ResolveOne"; host: string; emit: boolean }
  | { _tag: "ResolveAll"; emit: boolean };
export type TagResolveArgv = { _tag: "ParsedTagResolve"; action: TagResolveAction }
  | { _tag: "OtherFirnCommand"; argv: string[] }
  | { _tag: "InvalidTagResolveArgv"; argv: string[] };
export type TagResolveHostData = { tags: r.HostTags; tagSourcePresent: boolean; active: string[] };
export function makeTagResolveHostData(tags: r.HostTags, tagSourcePresent: boolean, active: string[]): TagResolveHostData { return { tags, tagSourcePresent, active }; }
export type TagResolveRepositoryData = { modules: r.ModuleTags[]; hosts: TagResolveHostData[] };
export function makeTagResolveRepositoryData(modules: r.ModuleTags[], hosts: TagResolveHostData[]): TagResolveRepositoryData { return { modules, hosts }; }
export type HostLookup = { _tag: "FoundHost"; data: TagResolveHostData }
  | { _tag: "MissingHost"; host: string };
export type TagResolveEffect = { _tag: "StdoutText"; text: string }
  | { _tag: "StderrText"; text: string }
  | { _tag: "BuildGenerated"; path: string };
export type TagResolveOutcome = { status: number; effects: TagResolveEffect[] };
export function makeTagResolveOutcome(status: number, effects: TagResolveEffect[]): TagResolveOutcome { return { status, effects }; }

export function emitSuffix(leaf: string): boolean {
  const length: number = leaf.length;
  return ((length >= 5) && (leaf.slice((length - 5), length) === "+emit"));
}

export function actionFromLeaf(leaf: string, firnTagEmit: boolean): TagResolveAction {
  const suffix: boolean = emitSuffix(leaf);
  const target: string = (suffix ? leaf.slice(0, (leaf.length - 5)) : leaf);
  const emit: boolean = (suffix || firnTagEmit);
  if ((target === "all")) {
    return { _tag: "ResolveAll" as const, emit: emit };
  }
  return { _tag: "ResolveOne" as const, host: target, emit: emit };
}

export function parseTagResolveArgv(argv: string[], defaultHost: string, firnTagEmit: boolean): TagResolveArgv {
  if (((argv.length >= 2) && (argv[0] === "tag") && (argv[1] === "resolve"))) {
    if ((argv.length === 2)) {
      return { _tag: "ParsedTagResolve" as const, action: actionFromLeaf(defaultHost, firnTagEmit) };
    }else if ((argv.length === 3)) {
      return { _tag: "ParsedTagResolve" as const, action: actionFromLeaf(argv[2], firnTagEmit) };
    }else {
      return { _tag: "InvalidTagResolveArgv" as const, argv: argv };
    }
  }
  return { _tag: "OtherFirnCommand" as const, argv: argv };
}

export function actionHost(action: TagResolveAction): string {
  const matched41 = action;
  switch (matched41._tag) {
    case "ResolveOne": {
      const host = matched41.host;
      const emit = matched41.emit;
      return host;
    }
    case "ResolveAll": {
      const emit = matched41.emit;
      return "all";
    }
  }
}

export function actionEmit(action: TagResolveAction): boolean {
  const matched42 = action;
  switch (matched42._tag) {
    case "ResolveOne": {
      const host = matched42.host;
      const emit = matched42.emit;
      return emit;
    }
    case "ResolveAll": {
      const emit = matched42.emit;
      return emit;
    }
  }
}

export function actionAll(action: TagResolveAction): boolean {
  const matched43 = action;
  switch (matched43._tag) {
    case "ResolveOne": {
      const host = matched43.host;
      const emit = matched43.emit;
      return false;
    }
    case "ResolveAll": {
      const emit = matched43.emit;
      return true;
    }
  }
}

export function hostDataName(data: TagResolveHostData): string {
  return data.tags.host;
}

export function repositoryHostNames(repository: TagResolveRepositoryData): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= repository.hosts.length)) {
      return result.slice().sort();
    }
    [index, result] = [(index + 1), [...result, hostDataName(repository.hosts[index])]];
    continue;
  }
}

export function findHost(repository: TagResolveRepositoryData, host: string): HostLookup {
  let index: number = 0;
  while (true) {
    if ((index >= repository.hosts.length)) {
      return { _tag: "MissingHost" as const, host: host };
    }
    const data: TagResolveHostData = repository.hosts[index];
    if ((hostDataName(data) === host)) {
      return { _tag: "FoundHost" as const, data: data };
    }
    index = (index + 1);
    continue;
  }
}

export function joinHostNames(hosts: string[]): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= hosts.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + ((index === 0) ? "" : ", ") + hosts[index])];
    continue;
  }
}

export function validationErrorHint(error: r.ValidationError): string {
  const matched47 = error;
  switch (matched47._tag) {
    case "UnknownPlatform": {
      const host = matched47.host;
      const platform = matched47.platform;
      const hint = matched47.hint;
      return hint;
    }
    case "UnknownTag": {
      const host = matched47.host;
      const tag = matched47.tag;
      const hint = matched47.hint;
      return hint;
    }
    case "OptInMismatch": {
      const host = matched47.host;
      const tag = matched47.tag;
      const module = matched47.module;
      const hint = matched47.hint;
      return hint;
    }
    case "UnknownDisabled": {
      const host = matched47.host;
      const module = matched47.module;
      const hint = matched47.hint;
      return hint;
    }
  }
}

export function errorEffects(errors: r.ValidationError[]): TagResolveEffect[] {
  let index: number = 0;
  let result: TagResolveEffect[] = [];
  while (true) {
    if ((index >= errors.length)) {
      return result;
    }
    [index, result] = [(index + 1), [...result, { _tag: "StderrText" as const, text: ("" + "tag-resolve: " + validationErrorHint(errors[index]) + "\n") }]];
    continue;
  }
}

export function warningEffects(warnings: string[]): TagResolveEffect[] {
  let index: number = 0;
  let result: TagResolveEffect[] = [];
  while (true) {
    if ((index >= warnings.length)) {
      return result;
    }
    [index, result] = [(index + 1), [...result, { _tag: "StderrText" as const, text: ("" + "tag-resolve: warning: " + warnings[index] + "\n") }]];
    continue;
  }
}

export function resolutionTags(resolution: r.Resolution): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= resolution.perTag.length)) {
      return result.slice().sort();
    }
    [index, result] = [(index + 1), [...result, resolution.perTag[index].tag]];
    continue;
  }
}

export function renderModuleLines(modules: string[]): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + "    " + modules[index] + "\n")];
    continue;
  }
}

export function renderTagContributions(resolution: r.Resolution): string {
  const tags: string[] = resolutionTags(resolution);
  if ((tags.length === 0)) {
    return "  (no tags enabled)\n";
  }
  let index: number = 0;
  let result: string = "Per-tag contributions:\n";
  while (true) {
    if ((index >= tags.length)) {
      return result;
    }
    const tag: string = tags[index];
    const modules: string[] = r.contributionFor(resolution, tag);
    [index, result] = [(index + 1), ("" + result + "  " + tag + " (" + modules.length + "):\n" + ((modules.length === 0) ? "    (none)\n" : renderModuleLines(modules)))];
    continue;
  }
}

export function renderOverrideLines(values: r.OverrideValue[]): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    const value: r.OverrideValue = values[index];
    [index, result] = [(index + 1), ("" + result + "      " + value.path + " = " + value.literal + "\n")];
    continue;
  }
}

export function renderActiveModules(resolution: r.Resolution): string {
  const active: string[] = resolution.active;
  let index: number = 0;
  let result: string = ("" + "Active modules (" + active.length + "):\n");
  while (true) {
    if ((index >= active.length)) {
      return result;
    }
    const module: string = active[index];
    [index, result] = [(index + 1), ("" + result + "  " + module + "\n" + renderOverrideLines(r.overridesFor(resolution, module)))];
    continue;
  }
}

export function renderPrettyResolution(resolution: r.Resolution): string {
  return ("" + "Host: " + resolution.host + "\n\n" + renderTagContributions(resolution) + "\n" + renderActiveModules(resolution));
}

export function generatedPath(host: string): string {
  return ("" + "hosts/" + host + "/tags.json");
}

export function emitSuccessEffects(resolution: r.Resolution): TagResolveEffect[] {
  const path: string = generatedPath(resolution.host);
  return [{ _tag: "BuildGenerated" as const, path: path }, { _tag: "StdoutText" as const, text: ("" + "tag-resolve: evaluated " + path + " (" + resolution.active.length + " modules)\n") }];
}

export function withActive(resolution: r.Resolution, active: string[]): r.Resolution {
  return r.makeResolution(resolution.host, active, resolution.perTag, resolution.overrides, resolution.errors, resolution.warnings);
}

export function resolveOne(modules: r.ModuleTags[], data: TagResolveHostData, emit: boolean): TagResolveOutcome {
  const resolution: r.Resolution = withActive(r.resolve(modules, data.tags), data.active);
  if ((resolution.errors.length > 0)) {
    return makeTagResolveOutcome(1, errorEffects(resolution.errors));
  }
  return makeTagResolveOutcome(0, [...warningEffects(resolution.warnings), ...(emit ? emitSuccessEffects(resolution) : [{ _tag: "StdoutText" as const, text: renderPrettyResolution(resolution) }])]);
}

export function appendAllPrettyGap(effects: TagResolveEffect[], emit: boolean): TagResolveEffect[] {
  if (emit) {
    return effects;
  }
  return [...effects, { _tag: "StdoutText" as const, text: "\n" }];
}

export function runAll(repository: TagResolveRepositoryData, hosts: string[], index: number, emit: boolean, effects: TagResolveEffect[]): TagResolveOutcome {
  if ((index >= hosts.length)) {
    return makeTagResolveOutcome(0, effects);
  }
  const matched55 = findHost(repository, hosts[index]);
  switch (matched55._tag) {
    case "MissingHost": {
      const host = matched55.host;
      return makeTagResolveOutcome(1, effects);
    }
    case "FoundHost": {
      const data = matched55.data;
      if ((emit && (!data.tagSourcePresent))) {
        return runAll(repository, hosts, (index + 1), emit, effects);
      }
      const outcome: TagResolveOutcome = resolveOne(repository.modules, data, emit);
      const nextEffects: TagResolveEffect[] = [...effects, ...outcome.effects];
      if ((outcome.status === 0)) {
        return runAll(repository, hosts, (index + 1), emit, appendAllPrettyGap(nextEffects, emit));
      }
      return makeTagResolveOutcome(outcome.status, nextEffects);
    }
  }
}

export function unknownHostOutcome(repository: TagResolveRepositoryData, host: string): TagResolveOutcome {
  return makeTagResolveOutcome(1, [{ _tag: "StderrText" as const, text: ("" + "firn tag resolve: no such host '" + host + "' (have: " + joinHostNames(repositoryHostNames(repository)) + ")\n") }]);
}

export function runTagResolveAction(repository: TagResolveRepositoryData, action: TagResolveAction): TagResolveOutcome {
  const matched56 = action;
  switch (matched56._tag) {
    case "ResolveAll": {
      const emit = matched56.emit;
      return runAll(repository, repositoryHostNames(repository), 0, emit, []);
    }
    case "ResolveOne": {
      const host = matched56.host;
      const emit = matched56.emit;
      const matched57 = findHost(repository, host);
      switch (matched57._tag) {
        case "MissingHost": {
          const missing = matched57.host;
          return unknownHostOutcome(repository, missing);
        }
        case "FoundHost": {
          const data = matched57.data;
          return resolveOne(repository.modules, data, emit);
        }
      }
    }
  }
}

export function outcomeStdout(outcome: TagResolveOutcome): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= outcome.effects.length)) {
      return result;
    }
    const effect: TagResolveEffect = outcome.effects[index];
    const matched59 = effect;
    switch (matched59._tag) {
      case "StdoutText": {
        const text = matched59.text;
        [index, result] = [(index + 1), ("" + result + text)];
        continue;
      }
      case "StderrText": {
        const text = matched59.text;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "BuildGenerated": {
        const path = matched59.path;
        [index, result] = [(index + 1), result];
        continue;
      }
    }
  }
}

export function outcomeStderr(outcome: TagResolveOutcome): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= outcome.effects.length)) {
      return result;
    }
    const effect: TagResolveEffect = outcome.effects[index];
    const matched61 = effect;
    switch (matched61._tag) {
      case "StdoutText": {
        const text = matched61.text;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "StderrText": {
        const text = matched61.text;
        [index, result] = [(index + 1), ("" + result + text)];
        continue;
      }
      case "BuildGenerated": {
        const path = matched61.path;
        [index, result] = [(index + 1), result];
        continue;
      }
    }
  }
}

export function outcomeEffectKinds(outcome: TagResolveOutcome): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= outcome.effects.length)) {
      return result;
    }
    const effect: TagResolveEffect = outcome.effects[index];
    [index, result] = [(index + 1), [...result, (() => {
      const matched63 = effect;
      switch (matched63._tag) {
        case "StdoutText": {
          const text = matched63.text;
          return "stdout";
        }
        case "StderrText": {
          const text = matched63.text;
          return "stderr";
        }
        case "BuildGenerated": {
          const path = matched63.path;
          return "build";
        }
      }
    })()]];
    continue;
  }
}
