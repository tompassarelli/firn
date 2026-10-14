import * as r from './tag_resolve.ts';
type ModuleState = { path: string; enabled: boolean };
function makeModuleState(path: string, enabled: boolean): ModuleState { return { path, enabled }; }
export type HostConfig = { host: string; references: string[]; states: ModuleState[] };
export function makeHostConfig(host: string, references: string[], states: ModuleState[]): HostConfig { return { host, references, states }; }
export type InventoryHost = { host: string; active: string[]; config: HostConfig };
export function makeInventoryHost(host: string, active: string[], config: HostConfig): InventoryHost { return { host, active, config }; }
export type InventoryRepository = { modules: r.ModuleTags[]; hosts: InventoryHost[] };
export function makeInventoryRepository(modules: r.ModuleTags[], hosts: InventoryHost[]): InventoryRepository { return { modules, hosts }; }
export type InventoryAction = { _tag: "ModuleListAll"; token: boolean }
  | { _tag: "ModuleListUsed"; token: boolean }
  | { _tag: "ModuleListUnused"; token: boolean }
  | { _tag: "ModuleRefs"; name: string }
  | { _tag: "ModuleStatus"; host: string }
  | { _tag: "HostList"; token: boolean }
  | { _tag: "HostStatus"; host: string };
export type InventoryArgv = { _tag: "ParsedInventory"; action: InventoryAction }
  | { _tag: "InvalidInventoryArgv"; argv: string[] };
export type InventoryRenderResult = { _tag: "InventoryRendered"; text: string }
  | { _tag: "InventoryHostMissing"; host: string };
const modulePrefix: string = "myConfig.modules.";
const enableSuffix: string = ".enable";

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

function appendUnique(values: string[], candidate: string): string[] {
  if (stringMember(values, candidate)) {
    return values;
  }
  return [...values, candidate];
}

function endsWith(text: string, suffix: string): boolean {
  return ((text.length >= suffix.length) && (text.slice((text.length - suffix.length), text.length) === suffix));
}

function stripEnableSuffix(path: string): string {
  if (endsWith(path, enableSuffix)) {
    return path.slice(0, (path.length - enableSuffix.length));
  }
  return path;
}

function enableStates(modules: string[], enabled: boolean, states: ModuleState[]): ModuleState[] {
  let index: number = 0;
  let result: ModuleState[] = states;
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    [index, result] = [(index + 1), [...result, makeModuleState(("" + modulePrefix + modules[index] + enableSuffix), enabled)]];
    continue;
  }
}

export function hostConfig(host: string, turnedOn: string[], turnedOff: string[]): HostConfig {
  let index: number = 0;
  let references: string[] = [];
  while (true) {
    if ((index >= turnedOff.length)) {
      return makeHostConfig(host, (() => {
        let onIndex: number = 0;
        let combined: string[] = references;
        while (true) {
          if ((onIndex >= turnedOn.length)) {
            return combined;
          }
          [onIndex, combined] = [(onIndex + 1), appendUnique(combined, turnedOn[onIndex])];
          continue;
        }
      })().slice().sort(), enableStates(turnedOff, false, enableStates(turnedOn, true, [])));
    }
    [index, references] = [(index + 1), appendUnique(references, turnedOff[index])];
    continue;
  }
}

function inventoryHostName(host: InventoryHost): string {
  return host.host;
}

function moduleNames(repository: InventoryRepository): string[] {
  let index: number = 0;
  let names: string[] = [];
  while (true) {
    if ((index >= repository.modules.length)) {
      return names.slice().sort();
    }
    [index, names] = [(index + 1), [...names, repository.modules[index].name]];
    continue;
  }
}

function hostNames(repository: InventoryRepository): string[] {
  let index: number = 0;
  let names: string[] = [];
  while (true) {
    if ((index >= repository.hosts.length)) {
      return names.slice().sort();
    }
    [index, names] = [(index + 1), [...names, inventoryHostName(repository.hosts[index])]];
    continue;
  }
}

export function tagActive(repository: InventoryRepository, host: InventoryHost): string[] {
  return host.active;
}

export function liveModules(repository: InventoryRepository): string[] {
  let index: number = 0;
  let live: string[] = [];
  while (true) {
    if ((index >= repository.hosts.length)) {
      return live.slice().sort();
    }
    const host: InventoryHost = repository.hosts[index];
    const direct: string[] = host.config.references;
    const tagged: string[] = tagActive(repository, host);
    [index, live] = [(index + 1), (() => {
      let directIndex: number = 0;
      let combined: string[] = live;
      while (true) {
        if ((directIndex >= direct.length)) {
          let tagIndex: number = 0;
          let tagCombined: string[] = combined;
          while (true) {
            if ((tagIndex >= tagged.length)) {
              return tagCombined;
            }
            [tagIndex, tagCombined] = [(tagIndex + 1), appendUnique(tagCombined, tagged[tagIndex])];
            continue;
          }
        }
        [directIndex, combined] = [(directIndex + 1), appendUnique(combined, direct[directIndex])];
        continue;
      }
    })()];
    continue;
  }
}

export function unusedModules(repository: InventoryRepository): string[] {
  const live: string[] = liveModules(repository);
  const all: string[] = moduleNames(repository);
  let index: number = 0;
  let unused: string[] = [];
  while (true) {
    if ((index >= all.length)) {
      return unused;
    }
    const name: string = all[index];
    [index, unused] = [(index + 1), (stringMember(live, name) ? unused : [...unused, name])];
    continue;
  }
}

export function directHosts(repository: InventoryRepository, module: string): string[] {
  let index: number = 0;
  let hosts: string[] = [];
  while (true) {
    if ((index >= repository.hosts.length)) {
      return hosts.slice().sort();
    }
    const host: InventoryHost = repository.hosts[index];
    [index, hosts] = [(index + 1), (stringMember(host.config.references, module) ? [...hosts, inventoryHostName(host)] : hosts)];
    continue;
  }
}

export function tagHosts(repository: InventoryRepository, module: string): string[] {
  let index: number = 0;
  let hosts: string[] = [];
  while (true) {
    if ((index >= repository.hosts.length)) {
      return hosts.slice().sort();
    }
    const host: InventoryHost = repository.hosts[index];
    [index, hosts] = [(index + 1), (stringMember(tagActive(repository, host), module) ? [...hosts, inventoryHostName(host)] : hosts)];
    continue;
  }
}

function joinStrings(values: string[]): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + ((index === 0) ? "" : ", ") + values[index])];
    continue;
  }
}

function sourceLabels(repository: InventoryRepository, module: string): string[] {
  const direct: string[] = directHosts(repository, module);
  const tagged: string[] = tagHosts(repository, module);
  let index: number = 0;
  let labels: string[] = direct;
  while (true) {
    if ((index >= tagged.length)) {
      return labels;
    }
    [index, labels] = [(index + 1), appendUnique(labels, ("" + "via tag@" + tagged[index]))];
    continue;
  }
}

export function renderLines(values: string[], prefix: string): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + prefix + values[index] + "\n")];
    continue;
  }
}

export function renderModuleListAll(modules: string[]): string {
  let index: number = 0;
  let result: string = ("" + "Modules (" + modules.length + "):\n");
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    [index, result] = [(index + 1), ("" + result + "  myConfig.modules." + modules[index] + "\n")];
    continue;
  }
}

export function renderModuleListUsed(repository: InventoryRepository): string {
  const modules: string[] = liveModules(repository);
  let index: number = 0;
  let result: string = ("" + "Used modules (" + modules.length + "):\n");
  while (true) {
    if ((index >= modules.length)) {
      return result;
    }
    const module: string = modules[index];
    const labels: string[] = sourceLabels(repository, module);
    [index, result] = [(index + 1), ("" + result + "  " + module + "  (" + ((labels.length === 0) ? "\u2014" : joinStrings(labels)) + ")\n")];
    continue;
  }
}

export function renderModuleListUnused(repository: InventoryRepository): string {
  const modules: string[] = unusedModules(repository);
  return ("" + "Unreferenced modules (" + modules.length + "):\n" + renderLines(modules, "  "));
}

export function renderHostList(hosts: string[]): string {
  return ("" + "Hosts (" + hosts.length + "):\n" + renderLines(hosts, "  "));
}

export function renderHostSection(hosts: string[]): string {
  if ((hosts.length === 0)) {
    return "  (none)\n";
  }
  return renderLines(hosts, "  ");
}

export function renderModuleRefs(repository: InventoryRepository, module: string): string {
  return ("" + "Hosts (direct, from configuration.nix):\n" + renderHostSection(directHosts(repository, module)) + "\nHosts (via tag resolution):\n" + renderHostSection(tagHosts(repository, module)));
}

export function statePaths(config: HostConfig, enabled: boolean): string[] {
  let index: number = 0;
  let paths: string[] = [];
  while (true) {
    if ((index >= config.states.length)) {
      return paths.slice().sort();
    }
    const state: ModuleState = config.states[index];
    [index, paths] = [(index + 1), ((enabled === state.enabled) ? [...paths, stripEnableSuffix(state.path)] : paths)];
    continue;
  }
}

export function renderHostStatus(config: HostConfig): string {
  const host: string = config.host;
  const enabled: string[] = statePaths(config, true);
  const disabled: string[] = statePaths(config, false);
  return ("" + "Enabled in " + host + ":\n" + renderLines(enabled, "  ") + ((disabled.length === 0) ? "" : ("" + "\nExplicitly disabled in " + host + ":\n" + renderLines(disabled, "  "))));
}

function findHostConfig(repository: InventoryRepository, wanted: string): HostConfig | null {
  let index: number = 0;
  while (true) {
    if ((index >= repository.hosts.length)) {
      return null;
    }
    const host: InventoryHost = repository.hosts[index];
    if ((wanted === inventoryHostName(host))) {
      return host.config;
    }
    index = (index + 1);
    continue;
  }
}

export function parseInventoryArgv(argv: string[], defaultHost: string): InventoryArgv {
  if (((argv.length === 2) && (argv[0] === "module") && (argv[1] === "list"))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "ModuleListAll" as const, token: false } };
  }else if (((argv.length === 3) && (argv[0] === "module") && (argv[1] === "list") && (argv[2] === "all"))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "ModuleListAll" as const, token: false } };
  }else if (((argv.length === 3) && (argv[0] === "module") && (argv[1] === "list") && (argv[2] === "used"))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "ModuleListUsed" as const, token: false } };
  }else if (((argv.length === 3) && (argv[0] === "module") && (argv[1] === "list") && (argv[2] === "unused"))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "ModuleListUnused" as const, token: false } };
  }else if (((argv.length === 3) && (argv[0] === "module") && (argv[1] === "refs"))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "ModuleRefs" as const, name: argv[2] } };
  }else if ((((argv.length === 2) || (argv.length === 3)) && (argv[0] === "module") && (argv[1] === "status") && ((argv.length === 2) || (argv[2] === "all")))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "ModuleStatus" as const, host: defaultHost } };
  }else if ((((argv.length === 2) || (argv.length === 3)) && (argv[0] === "host") && (argv[1] === "list") && ((argv.length === 2) || (argv[2] === "all")))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "HostList" as const, token: false } };
  }else if ((((argv.length === 2) || (argv.length === 3)) && (argv[0] === "host") && (argv[1] === "status"))) {
    return { _tag: "ParsedInventory" as const, action: { _tag: "HostStatus" as const, host: ((argv.length === 2) ? defaultHost : (((argv[2] === "current") || (argv[2] === "all")) ? defaultHost : argv[2])) } };
  }else {
    return { _tag: "InvalidInventoryArgv" as const, argv: argv };
  }
}

export function renderAction(repository: InventoryRepository, action: InventoryAction): InventoryRenderResult {
  const matched174 = action;
  switch (matched174._tag) {
    case "ModuleListAll": {
      const token = matched174.token;
      return { _tag: "InventoryRendered" as const, text: renderModuleListAll(moduleNames(repository)) };
    }
    case "ModuleListUsed": {
      const token = matched174.token;
      return { _tag: "InventoryRendered" as const, text: renderModuleListUsed(repository) };
    }
    case "ModuleListUnused": {
      const token = matched174.token;
      return { _tag: "InventoryRendered" as const, text: renderModuleListUnused(repository) };
    }
    case "ModuleRefs": {
      const name = matched174.name;
      return { _tag: "InventoryRendered" as const, text: renderModuleRefs(repository, name) };
    }
    case "HostList": {
      const token = matched174.token;
      return { _tag: "InventoryRendered" as const, text: renderHostList(hostNames(repository)) };
    }
    case "ModuleStatus": {
      const host = matched174.host;
      const config: HostConfig | null = findHostConfig(repository, host);
      if ((config !== null)) {
        return { _tag: "InventoryRendered" as const, text: renderHostStatus(config) };
      }
      return { _tag: "InventoryHostMissing" as const, host: host };
    }
    case "HostStatus": {
      const host = matched174.host;
      const config: HostConfig | null = findHostConfig(repository, host);
      if ((config !== null)) {
        return { _tag: "InventoryRendered" as const, text: renderHostStatus(config) };
      }
      return { _tag: "InventoryHostMissing" as const, host: host };
    }
  }
}
