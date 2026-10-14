import * as r from './tag_resolve.ts';
import * as driver from './tag_resolve_driver.ts';
import * as input from './tag_inputs.ts';
const maxSourceBytes: number = 16777216;
const maxDirectoryEntries: number = 16384;
export type DirectoryNamesResult = { _tag: "DirectoryNamesLoaded"; names: string[] }
  | { _tag: "DirectoryNamesRejected"; message: string };
export type ModulesLoadResult = { _tag: "ModulesLoaded"; modules: r.ModuleTags[] }
  | { _tag: "ModulesRejected"; message: string };
export type HostLoadResult = { _tag: "HostLoaded"; data: driver.TagResolveHostData }
  | { _tag: "HostRejected"; message: string };
export type HostsLoadResult = { _tag: "HostsLoaded"; hosts: driver.TagResolveHostData[] }
  | { _tag: "HostsRejected"; message: string };
export type HostFactsLoadResult = { _tag: "HostFactsLoaded"; facts: any }
  | { _tag: "HostFactsRejected"; message: string };
export type AllowlistLoadResult = { _tag: "AllowlistLoaded"; modules: string[] }
  | { _tag: "AllowlistRejected"; message: string };

function path(root: string, relative: string): string {
  return ("" + root + "/" + relative);
}

function errnoMessage(operation: string, relative: string, errno: number): string {
  return ("" + "firn tag resolve: " + operation + " '" + relative + "': errno " + errno + "\n");
}

function parseMessage(kind: string, relative: string, message: string, offset: number): string {
  return ("" + "firn tag resolve: invalid " + kind + " '" + relative + "' at offset " + offset + ": " + message + "\n");
}

export function directoryNames(bridge: any, root: string, relative: string): DirectoryNamesResult {
  const absolute: string = path(root, relative);
  const result: any = bridge.listDirectory(absolute, maxDirectoryEntries);
  const errno: number = bridge.status(result);
  if ((!(errno === 0))) {
    if ((errno === 2)) {
      return { _tag: "DirectoryNamesLoaded" as const, names: [] };
    }
    return { _tag: "DirectoryNamesRejected" as const, message: errnoMessage("cannot list", relative, errno) };
  }
  const entries: string[] = bridge.value(result);
  let index: number = 0;
  let names: string[] = [];
  while (true) {
    if ((index >= entries.length)) {
      return { _tag: "DirectoryNamesLoaded" as const, names: names.slice().sort() };
    }
    const name: string = entries[index];
    const candidate: string = ("" + absolute + "/" + name);
    const kindResult: any = bridge.pathKind(candidate);
    const kindErrno: number = bridge.status(kindResult);
    if ((kindErrno === 0)) {
      const kind: number = bridge.value(kindResult);
      [index, names] = [(index + 1), ((kind === 2) ? [...names, name] : names)];
      continue;
    }
    if ((kindErrno === 2)) {
      [index, names] = [(index + 1), names];
      continue;
    }
    return { _tag: "DirectoryNamesRejected" as const, message: errnoMessage("cannot inspect", ("" + relative + "/" + name), kindErrno) };
  }
}

function overrideValues(bridge: any, facts: any, name: string, tag: string): r.OverrideValue[] {
  let paths: string[] = bridge.factOverridePaths(facts, name, tag);
  let values: r.OverrideValue[] = [];
  while (true) {
    if ((paths.length === 0)) {
      return values;
    }
    const overridePath: string = paths[0];
    const literal: string = bridge.factOverrideLiteral(facts, name, tag, overridePath);
    [paths, values] = [paths.slice(1), [...values, r.makeOverrideValue(overridePath, literal)]];
    continue;
  }
}

function moduleOverrides(bridge: any, facts: any, name: string): r.TaggedOverrides[] {
  let tags: string[] = bridge.factOverrideTags(facts, name);
  let overrides: r.TaggedOverrides[] = [];
  while (true) {
    if ((tags.length === 0)) {
      return overrides;
    }
    const tag: string = tags[0];
    [tags, overrides] = [tags.slice(1), [...overrides, r.makeTaggedOverrides(tag, overrideValues(bridge, facts, name, tag))]];
    continue;
  }
}

function modulesFromFacts(bridge: any, facts: any, names: string[]): r.ModuleTags[] {
  let remaining: string[] = names;
  let modules: r.ModuleTags[] = [];
  while (true) {
    if ((remaining.length === 0)) {
      return modules;
    }
    const name: string = remaining[0];
    const tags: string[] = bridge.factTags(facts, name);
    const optIn: string[] = bridge.factOptIn(facts, name);
    [remaining, modules] = [remaining.slice(1), [...modules, r.makeModuleTags(name, tags, optIn, moduleOverrides(bridge, facts, name))]];
    continue;
  }
}

export function loadModules(bridge: any, root: string): ModulesLoadResult {
  const matched68 = directoryNames(bridge, root, "modules");
  switch (matched68._tag) {
    case "DirectoryNamesRejected": {
      const message = matched68.message;
      return { _tag: "ModulesRejected" as const, message: message };
    }
    case "DirectoryNamesLoaded": {
      const names = matched68.names;
      const result: any = bridge.readModuleFacts(root);
      const status: number = bridge.status(result);
      if ((status === 0)) {
        return { _tag: "ModulesLoaded" as const, modules: modulesFromFacts(bridge, bridge.value(result), names) };
      }
      return { _tag: "ModulesRejected" as const, message: ("" + "firn: cannot load module tags from metadata: " + bridge.moduleFactsMessage(result) + "\n") };
    }
  }
}

export function loadDarwinAllowlist(bridge: any, root: string): AllowlistLoadResult {
  const relative: string = "config/darwin-modules.json";
  const absolute: string = path(root, relative);
  const result: any = bridge.readText(absolute, maxSourceBytes);
  const errno: number = bridge.status(result);
  if ((!(errno === 0))) {
    return { _tag: "AllowlistRejected" as const, message: errnoMessage("cannot read", relative, errno) };
  }
  const source: string = bridge.value(result);
  const matched69 = input.darwinAllowlistFromJson(source);
  switch (matched69._tag) {
    case "DarwinAllowlistParsed": {
      const modules = matched69.modules;
      return { _tag: "AllowlistLoaded" as const, modules: modules };
    }
    case "DarwinAllowlistRejected": {
      const message = matched69.message;
      const offset = matched69.offset;
      return { _tag: "AllowlistRejected" as const, message: parseMessage("Darwin allowlist", relative, message, offset) };
    }
  }
}

function emptyHost(host: string): r.HostTags {
  return r.makeHostTags(host, [], [], "linux", false, []);
}

function enabledTags(bridge: any, facts: any, host: string): r.EnabledTag[] {
  let tags: string[] = bridge.hostEnabledTags(facts, host);
  let result: r.EnabledTag[] = [];
  while (true) {
    if ((tags.length === 0)) {
      return result;
    }
    const tag: string = tags[0];
    [tags, result] = [tags.slice(1), [...result, r.makeEnabledTag(tag, bridge.hostAdds(facts, host, tag), bridge.hostDrops(facts, host, tag))]];
    continue;
  }
}

function hostTags(bridge: any, facts: any, host: string, platform: string, allowed: string[]): r.HostTags {
  return r.makeHostTags(host, enabledTags(bridge, facts, host), bridge.hostDisabled(facts, host), platform, (platform === "darwin"), allowed);
}

function hostFromFacts(bridge: any, root: string, facts: any, host: string): HostLoadResult {
  if ((!bridge.hostDeclared(facts, host))) {
    return { _tag: "HostLoaded" as const, data: driver.makeTagResolveHostData(emptyHost(host), false, []) };
  }
  const platform: string = bridge.hostPlatform(facts, host);
  const active: string[] = bridge.hostActive(facts, host);
  if ((platform === "darwin")) {
    const matched71 = loadDarwinAllowlist(bridge, root);
    switch (matched71._tag) {
      case "AllowlistRejected": {
        const message = matched71.message;
        return { _tag: "HostRejected" as const, message: message };
      }
      case "AllowlistLoaded": {
        const allowed = matched71.modules;
        return { _tag: "HostLoaded" as const, data: driver.makeTagResolveHostData(hostTags(bridge, facts, host, platform, allowed), true, active) };
      }
    }
  }
  return { _tag: "HostLoaded" as const, data: driver.makeTagResolveHostData(hostTags(bridge, facts, host, platform, []), true, active) };
}

function readHostFacts(bridge: any, root: string): HostFactsLoadResult {
  const result: any = bridge.readHostFacts(root);
  if ((bridge.status(result) === 0)) {
    return { _tag: "HostFactsLoaded" as const, facts: bridge.value(result) };
  }
  return { _tag: "HostFactsRejected" as const, message: ("" + "firn: cannot load host tags from metadata: " + bridge.moduleFactsMessage(result) + "\n") };
}

export function loadHost(bridge: any, root: string, host: string): HostLoadResult {
  const matched72 = readHostFacts(bridge, root);
  switch (matched72._tag) {
    case "HostFactsRejected": {
      const message = matched72.message;
      return { _tag: "HostRejected" as const, message: message };
    }
    case "HostFactsLoaded": {
      const facts = matched72.facts;
      return hostFromFacts(bridge, root, facts, host);
    }
  }
}

function loadHostsFrom(bridge: any, root: string, facts: any, names: string[], index: number, hosts: driver.TagResolveHostData[]): HostsLoadResult {
  if ((index >= names.length)) {
    return { _tag: "HostsLoaded" as const, hosts: hosts };
  }
  const matched73 = hostFromFacts(bridge, root, facts, names[index]);
  switch (matched73._tag) {
    case "HostRejected": {
      const message = matched73.message;
      return { _tag: "HostsRejected" as const, message: message };
    }
    case "HostLoaded": {
      const data = matched73.data;
      return loadHostsFrom(bridge, root, facts, names, (index + 1), [...hosts, data]);
    }
  }
}

function loadHosts(bridge: any, root: string, names: string[], action: driver.TagResolveAction): HostsLoadResult {
  const matched74 = readHostFacts(bridge, root);
  switch (matched74._tag) {
    case "HostFactsRejected": {
      const message = matched74.message;
      return { _tag: "HostsRejected" as const, message: message };
    }
    case "HostFactsLoaded": {
      const facts = matched74.facts;
      return loadHostsFrom(bridge, root, facts, (driver.actionAll(action) ? names : [driver.actionHost(action)]), 0, []);
    }
  }
}

function stringMember(values: string[], candidate: string): boolean {
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

function placeholderHosts(names: string[]): driver.TagResolveHostData[] {
  let index: number = 0;
  let hosts: driver.TagResolveHostData[] = [];
  while (true) {
    if ((index >= names.length)) {
      return hosts;
    }
    [index, hosts] = [(index + 1), [...hosts, driver.makeTagResolveHostData(emptyHost(names[index]), false, [])]];
    continue;
  }
}

function emitIoError(bridge: any, message: string): number {
  bridge.err(message);
  return 1;
}

function anyTagSource(hosts: driver.TagResolveHostData[]): boolean {
  let index: number = 0;
  while (true) {
    if ((index >= hosts.length)) {
      return false;
    }
    if (hosts[index].tagSourcePresent) {
      return true;
    }
    index = (index + 1);
    continue;
  }
}

function executeEffects(bridge: any, root: string, outcome: driver.TagResolveOutcome, index: number): number {
  if ((index >= outcome.effects.length)) {
    return outcome.status;
  }
  const matched78 = outcome.effects[index];
  switch (matched78._tag) {
    case "StdoutText": {
      const text = matched78.text;
      bridge.out(text);
      return executeEffects(bridge, root, outcome, (index + 1));
    }
    case "StderrText": {
      const text = matched78.text;
      bridge.err(text);
      return executeEffects(bridge, root, outcome, (index + 1));
    }
    case "BuildGenerated": {
      const relative = matched78.path;
      const status: number = bridge.buildGenerated(root);
      if ((status === 0)) {
        return executeEffects(bridge, root, outcome, (index + 1));
      }
      return emitIoError(bridge, ("" + "firn tag resolve: Nix evaluation '" + relative + "' exited " + status + "\n"));
    }
  }
}

export function runAction(bridge: any, root: string, hostNames: string[], action: driver.TagResolveAction): number {
  if (((!driver.actionAll(action)) && (!stringMember(hostNames, driver.actionHost(action))))) {
    return executeEffects(bridge, root, driver.runTagResolveAction(driver.makeTagResolveRepositoryData([], placeholderHosts(hostNames)), action), 0);
  }
  const matched79 = loadHosts(bridge, root, hostNames, action);
  switch (matched79._tag) {
    case "HostsRejected": {
      const message = matched79.message;
      return emitIoError(bridge, message);
    }
    case "HostsLoaded": {
      const hosts = matched79.hosts;
      if ((driver.actionAll(action) && driver.actionEmit(action) && (!anyTagSource(hosts)))) {
        return executeEffects(bridge, root, driver.runTagResolveAction(driver.makeTagResolveRepositoryData([], hosts), action), 0);
      }
      const matched80 = loadModules(bridge, root);
      switch (matched80._tag) {
        case "ModulesRejected": {
          const message = matched80.message;
          return emitIoError(bridge, message);
        }
        case "ModulesLoaded": {
          const modules = matched80.modules;
          return executeEffects(bridge, root, driver.runTagResolveAction(driver.makeTagResolveRepositoryData(modules, hosts), action), 0);
        }
      }
    }
  }
}

function repositoryRoot(bridge: any): string | null {
  const explicit: string | null = bridge.env("FIRN_REPO");
  if ((explicit !== null)) {
    return explicit;
  }
  const home: string | null = bridge.env("HOME");
  if ((home !== null)) {
    return ("" + home + "/code/nixos-config/main");
  }
  return null;
}

function defaultHost(bridge: any): string {
  const host: string | null = bridge.env("FIRN_HOST");
  if ((host !== null)) {
    return host;
  }
  return "whiterabbit";
}

function usageError(bridge: any): number {
  bridge.err("Usage: firn tag resolve [<host>|all][+emit]\n");
  return 64;
}

export function run(bridge: any, args: string[]): number {
  const matched81 = driver.parseTagResolveArgv(args, defaultHost(bridge), (bridge.env("FIRN_TAG_EMIT") !== null));
  switch (matched81._tag) {
    case "OtherFirnCommand": {
      const argv = matched81.argv;
      return usageError(bridge);
    }
    case "InvalidTagResolveArgv": {
      const argv = matched81.argv;
      return usageError(bridge);
    }
    case "ParsedTagResolve": {
      const action = matched81.action;
      const root: string | null = repositoryRoot(bridge);
      if ((root === null)) {
        bridge.err("firn tag resolve: FIRN_REPO and HOME are not set\n");
        return 1;
      }
      const matched82 = directoryNames(bridge, root, "hosts");
      switch (matched82._tag) {
        case "DirectoryNamesRejected": {
          const message = matched82.message;
          return emitIoError(bridge, message);
        }
        case "DirectoryNamesLoaded": {
          const names = matched82.names;
          return runAction(bridge, root, names, action);
        }
      }
    }
  }
}
