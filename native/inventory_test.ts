import { isDeepStrictEqual } from 'node:util';
import * as i from './inventory.ts';
import * as r from './tag_resolve.ts';

function makeModule(seed: number, name: string, tags: string[]): r.ModuleTags {
  return r.makeModuleTags(name, tags, [], []);
}

function alphaConfig(seed: number): i.HostConfig {
  return i.hostConfig(("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"), [("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed))], [("" + "beta" + (isDeepStrictEqual(seed, 0) ? "" : seed))]);
}

function zetaConfig(seed: number): i.HostConfig {
  return i.hostConfig(("" + "zeta" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"), [("" + "beta" + (isDeepStrictEqual(seed, 0) ? "" : seed))], []);
}

function repository(seed: number): i.InventoryRepository {
  return i.makeInventoryRepository([makeModule(seed, ("" + "orphan" + (isDeepStrictEqual(seed, 0) ? "" : seed)), []), makeModule(seed, ("" + "gamma" + (isDeepStrictEqual(seed, 0) ? "" : seed)), [("" + "desktop" + (isDeepStrictEqual(seed, 0) ? "" : seed))]), makeModule(seed, ("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed)), []), makeModule(seed, ("" + "beta" + (isDeepStrictEqual(seed, 0) ? "" : seed)), [("" + "terminal" + (isDeepStrictEqual(seed, 0) ? "" : seed))])], [i.makeInventoryHost(("" + "zeta" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"), [("" + "gamma" + (isDeepStrictEqual(seed, 0) ? "" : seed))], zetaConfig(seed)), i.makeInventoryHost(("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"), [], alphaConfig(seed))]);
}

function caseCanonicalPathsAndStates(seed: number): boolean {
  const config: i.HostConfig = alphaConfig(seed);
  return (isDeepStrictEqual(config.references, [("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed)), ("" + "beta" + (isDeepStrictEqual(seed, 0) ? "" : seed))]) && isDeepStrictEqual(i.statePaths(config, true), [("" + "myConfig.modules.alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed))]) && isDeepStrictEqual(i.statePaths(config, false), [("" + "myConfig.modules.beta" + (isDeepStrictEqual(seed, 0) ? "" : seed))]));
}

function caseLiveClosure(seed: number): boolean {
  const repo: i.InventoryRepository = repository(seed);
  return (isDeepStrictEqual(i.liveModules(repo), [("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed)), ("" + "beta" + (isDeepStrictEqual(seed, 0) ? "" : seed)), ("" + "gamma" + (isDeepStrictEqual(seed, 0) ? "" : seed))]) && isDeepStrictEqual(i.unusedModules(repo), [("" + "orphan" + (isDeepStrictEqual(seed, 0) ? "" : seed))]) && isDeepStrictEqual(i.directHosts(repo, ("" + "beta" + (isDeepStrictEqual(seed, 0) ? "" : seed))), [("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"), ("" + "zeta" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host")]) && isDeepStrictEqual(i.tagHosts(repo, ("" + "beta" + (isDeepStrictEqual(seed, 0) ? "" : seed))), []) && isDeepStrictEqual(i.directHosts(repo, ("" + "gamma" + (isDeepStrictEqual(seed, 0) ? "" : seed))), []) && isDeepStrictEqual(i.tagHosts(repo, ("" + "gamma" + (isDeepStrictEqual(seed, 0) ? "" : seed))), [("" + "zeta" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host")]));
}

function moduleListAllAction(seed: number, action: i.InventoryAction): boolean {
  const matched185 = action;
  switch (matched185._tag) {
    case "ModuleListAll": {
      const token = matched185.token;
      return true;
    }
    case "ModuleListUsed": {
      const token = matched185.token;
      return false;
    }
    case "ModuleListUnused": {
      const token = matched185.token;
      return false;
    }
    case "ModuleRefs": {
      const name = matched185.name;
      return false;
    }
    case "ModuleStatus": {
      const host = matched185.host;
      return false;
    }
    case "HostList": {
      const token = matched185.token;
      return false;
    }
    case "HostStatus": {
      const host = matched185.host;
      return false;
    }
  }
}

function moduleStatusHost(seed: number, action: i.InventoryAction): string {
  const matched186 = action;
  switch (matched186._tag) {
    case "ModuleListAll": {
      const token = matched186.token;
      return "";
    }
    case "ModuleListUsed": {
      const token = matched186.token;
      return "";
    }
    case "ModuleListUnused": {
      const token = matched186.token;
      return "";
    }
    case "ModuleRefs": {
      const name = matched186.name;
      return "";
    }
    case "ModuleStatus": {
      const host = matched186.host;
      return host;
    }
    case "HostList": {
      const token = matched186.token;
      return "";
    }
    case "HostStatus": {
      const host = matched186.host;
      return "";
    }
  }
}

function hostStatusHost(seed: number, action: i.InventoryAction): string {
  const matched187 = action;
  switch (matched187._tag) {
    case "ModuleListAll": {
      const token = matched187.token;
      return "";
    }
    case "ModuleListUsed": {
      const token = matched187.token;
      return "";
    }
    case "ModuleListUnused": {
      const token = matched187.token;
      return "";
    }
    case "ModuleRefs": {
      const name = matched187.name;
      return "";
    }
    case "ModuleStatus": {
      const host = matched187.host;
      return "";
    }
    case "HostList": {
      const token = matched187.token;
      return "";
    }
    case "HostStatus": {
      const host = matched187.host;
      return host;
    }
  }
}

function caseArgvGrammar(seed: number): boolean {
  return ((() => {
    const matched188 = i.parseInventoryArgv(["module", "list"], ("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"));
    switch (matched188._tag) {
      case "ParsedInventory": {
        const action = matched188.action;
        return moduleListAllAction(seed, action);
      }
      case "InvalidInventoryArgv": {
        const argv = matched188.argv;
        return false;
      }
    }
  })() && (() => {
    const matched189 = i.parseInventoryArgv(["module", "status", "all"], ("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"));
    switch (matched189._tag) {
      case "ParsedInventory": {
        const action = matched189.action;
        return isDeepStrictEqual(moduleStatusHost(seed, action), ("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"));
      }
      case "InvalidInventoryArgv": {
        const argv = matched189.argv;
        return false;
      }
    }
  })() && (() => {
    const matched190 = i.parseInventoryArgv(["host", "status", ("" + "zeta" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host")], ("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"));
    switch (matched190._tag) {
      case "ParsedInventory": {
        const action = matched190.action;
        return isDeepStrictEqual(hostStatusHost(seed, action), ("" + "zeta" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"));
      }
      case "InvalidInventoryArgv": {
        const argv = matched190.argv;
        return false;
      }
    }
  })() && (() => {
    const matched191 = i.parseInventoryArgv(["module", "list", "stale"], ("" + "alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "-host"));
    switch (matched191._tag) {
      case "ParsedInventory": {
        const action = matched191.action;
        return false;
      }
      case "InvalidInventoryArgv": {
        const argv = matched191.argv;
        return true;
      }
    }
  })());
}

export function runScenarios(): number {
  if ((caseCanonicalPathsAndStates(0) && caseLiveClosure(0) && caseArgvGrammar(0))) {
    return 0;
  }
  console.log("FAIL inventory scenarios");
  return 1;
}
