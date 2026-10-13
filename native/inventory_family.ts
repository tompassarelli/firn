import * as inventory from './inventory.ts';
import * as tagFamily from './tag_resolve_family.ts';
type HostFactsResult = { _tag: "HostFactsRead"; facts: any }
  | { _tag: "HostFactsFailed"; message: string };
type RepositoryLoadResult = { _tag: "RepositoryLoaded"; repository: inventory.InventoryRepository }
  | { _tag: "RepositoryRejected"; message: string };

function readHostFacts(bridge: any, root: string): HostFactsResult {
  const result: any = bridge.readHostFacts(root);
  if ((bridge.status(result) === 0)) {
    return { _tag: "HostFactsRead" as const, facts: bridge.value(result) };
  }
  return { _tag: "HostFactsFailed" as const, message: ("" + "firn inventory: cannot load host facts through galileo query: " + bridge.moduleFactsMessage(result) + "\n") };
}

function hostConfig(bridge: any, facts: any, host: string): inventory.HostConfig {
  return inventory.hostConfig(host, bridge.hostTurnsOn(facts, host), bridge.hostTurnsOff(facts, host));
}

function inventoryHosts(bridge: any, facts: any, names: string[]): inventory.InventoryHost[] {
  let index: number = 0;
  let hosts: inventory.InventoryHost[] = [];
  while (true) {
    if ((index >= names.length)) {
      return hosts;
    }
    const host: string = names[index];
    [index, hosts] = [(index + 1), [...hosts, inventory.makeInventoryHost(host, bridge.hostActive(facts, host), hostConfig(bridge, facts, host))]];
    continue;
  }
}

function loadRepository(bridge: any, root: string): RepositoryLoadResult {
  const matched176 = tagFamily.loadModules(bridge, root);
  switch (matched176._tag) {
    case "ModulesRejected": {
      const message = matched176.message;
      return { _tag: "RepositoryRejected" as const, message: message };
    }
    case "ModulesLoaded": {
      const modules = matched176.modules;
      const matched177 = tagFamily.directoryNames(bridge, root, "hosts");
      switch (matched177._tag) {
        case "DirectoryNamesRejected": {
          const message = matched177.message;
          return { _tag: "RepositoryRejected" as const, message: message };
        }
        case "DirectoryNamesLoaded": {
          const names = matched177.names;
          const matched178 = readHostFacts(bridge, root);
          switch (matched178._tag) {
            case "HostFactsFailed": {
              const message = matched178.message;
              return { _tag: "RepositoryRejected" as const, message: message };
            }
            case "HostFactsRead": {
              const facts = matched178.facts;
              return { _tag: "RepositoryLoaded" as const, repository: inventory.makeInventoryRepository(modules, inventoryHosts(bridge, facts, names)) };
            }
          }
        }
      }
    }
  }
}

function emitError(bridge: any, message: string): number {
  bridge.err(message);
  return 1;
}

function printConfigStatus(bridge: any, root: string, host: string): number {
  const matched179 = readHostFacts(bridge, root);
  switch (matched179._tag) {
    case "HostFactsFailed": {
      const message = matched179.message;
      return emitError(bridge, message);
    }
    case "HostFactsRead": {
      const facts = matched179.facts;
      if (bridge.hostDeclared(facts, host)) {
        bridge.out(inventory.renderHostStatus(hostConfig(bridge, facts, host)));
        return 0;
      }
      return emitError(bridge, ("" + "firn inventory: no such host '" + host + "'\n"));
    }
  }
}

function printDirectoryList(bridge: any, root: string, relative: string, modules: boolean): number {
  const matched180 = tagFamily.directoryNames(bridge, root, relative);
  switch (matched180._tag) {
    case "DirectoryNamesRejected": {
      const message = matched180.message;
      return emitError(bridge, message);
    }
    case "DirectoryNamesLoaded": {
      const names = matched180.names;
      bridge.out((modules ? inventory.renderModuleListAll(names) : inventory.renderHostList(names)));
      return 0;
    }
  }
}

function printRepositoryAction(bridge: any, root: string, action: inventory.InventoryAction): number {
  const matched181 = loadRepository(bridge, root);
  switch (matched181._tag) {
    case "RepositoryRejected": {
      const message = matched181.message;
      return emitError(bridge, message);
    }
    case "RepositoryLoaded": {
      const repository = matched181.repository;
      const matched182 = inventory.renderAction(repository, action);
      switch (matched182._tag) {
        case "InventoryRendered": {
          const text = matched182.text;
          bridge.out(text);
          return 0;
        }
        case "InventoryHostMissing": {
          const host = matched182.host;
          return emitError(bridge, ("" + "firn inventory: no such host '" + host + "'\n"));
        }
      }
    }
  }
}

function runAction(bridge: any, root: string, action: inventory.InventoryAction): number {
  const matched183 = action;
  switch (matched183._tag) {
    case "ModuleListAll": {
      const token = matched183.token;
      return printDirectoryList(bridge, root, "modules", true);
    }
    case "ModuleListUsed": {
      const token = matched183.token;
      return printRepositoryAction(bridge, root, action);
    }
    case "ModuleListUnused": {
      const token = matched183.token;
      return printRepositoryAction(bridge, root, action);
    }
    case "ModuleRefs": {
      const name = matched183.name;
      return printRepositoryAction(bridge, root, action);
    }
    case "ModuleStatus": {
      const host = matched183.host;
      return printConfigStatus(bridge, root, host);
    }
    case "HostList": {
      const token = matched183.token;
      return printDirectoryList(bridge, root, "hosts", false);
    }
    case "HostStatus": {
      const host = matched183.host;
      return printConfigStatus(bridge, root, host);
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
  bridge.err(("" + "Usage: firn module list [all|used|unused]\n" + "       firn module refs <name>\n" + "       firn module status [all]\n" + "       firn host list [all]\n" + "       firn host status [<host>]\n"));
  return 64;
}

export function run(bridge: any, args: string[]): number {
  const matched184 = inventory.parseInventoryArgv(args, defaultHost(bridge));
  switch (matched184._tag) {
    case "InvalidInventoryArgv": {
      const argv = matched184.argv;
      return usageError(bridge);
    }
    case "ParsedInventory": {
      const action = matched184.action;
      const root: string | null = repositoryRoot(bridge);
      if ((root === null)) {
        return emitError(bridge, "firn inventory: FIRN_REPO and HOME are not set\n");
      }
      return runAction(bridge, root, action);
    }
  }
}
