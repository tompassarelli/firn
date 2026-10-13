import * as r from './tag_resolve.ts';
import * as repository from './tag_resolve_family.ts';
import * as resolveDriver from './tag_resolve_driver.ts';
import * as commands from './tag_commands.ts';
import * as driver from './tag_commands_driver.ts';
export type HostDocumentLoadResult = { _tag: "HostDocumentLoaded"; document: commands.HostDocument }
  | { _tag: "HostDocumentMissing"; host: string }
  | { _tag: "HostDocumentLoadRejected"; message: string };
export type HostDocumentsLoadResult = { _tag: "HostDocumentsLoaded"; documents: commands.HostDocument[] }
  | { _tag: "HostDocumentsLoadRejected"; message: string };

function path(root: string, relative: string): string {
  return ("" + root + "/" + relative);
}

function errnoMessage(label: string, operation: string, relative: string, errno: number): string {
  return ("" + label + ": " + operation + " '" + relative + "': errno " + errno + "\n");
}

function loadHostDocument(bridge: any, root: string, host: string): HostDocumentLoadResult {
  const matched137 = repository.loadHost(bridge, root, host);
  switch (matched137._tag) {
    case "HostRejected": {
      const message = matched137.message;
      return { _tag: "HostDocumentLoadRejected" as const, message: message };
    }
    case "HostLoaded": {
      const data = matched137.data;
      if (data.tagSourcePresent) {
        return { _tag: "HostDocumentLoaded" as const, document: commands.makeHostDocument(data.tags, data.active) };
      }
      return { _tag: "HostDocumentMissing" as const, host: host };
    }
  }
}

function loadActionHosts(bridge: any, root: string, action: driver.TagCommandAction): HostDocumentsLoadResult {
  const wanted: string | null = driver.actionHost(action);
  if ((wanted === null)) {
    return { _tag: "HostDocumentsLoaded" as const, documents: [] };
  }
  const host: string = wanted;
  const matched138 = loadHostDocument(bridge, root, host);
  switch (matched138._tag) {
    case "HostDocumentLoadRejected": {
      const message = matched138.message;
      return { _tag: "HostDocumentsLoadRejected" as const, message: message };
    }
    case "HostDocumentMissing": {
      const missing = matched138.host;
      return { _tag: "HostDocumentsLoaded" as const, documents: [] };
    }
    case "HostDocumentLoaded": {
      const document = matched138.document;
      return { _tag: "HostDocumentsLoaded" as const, documents: [document] };
    }
  }
}

function emitIoError(bridge: any, message: string): number {
  bridge.err(message);
  return 1;
}

function writeError(bridge: any, label: string, operation: string, relative: string, errno: number): number {
  return emitIoError(bridge, errnoMessage(label, operation, relative, errno));
}

function executeWrite(bridge: any, root: string, outcome: driver.TagCommandOutcome, index: number, relative: string, text: string, makeParents: boolean, label: string): number {
  const absolute: string = path(root, relative);
  if (makeParents) {
    const parentErrno: number = bridge.makeParentDirectories(absolute);
    if ((!(parentErrno === 0))) {
      return writeError(bridge, label, "cannot create parent for", relative, parentErrno);
    }
    const writeErrno: number = bridge.writeTextAtomic(absolute, text);
    if ((!(writeErrno === 0))) {
      return writeError(bridge, label, "cannot write", relative, writeErrno);
    }
    return executeEffects(bridge, root, outcome, (index + 1));
  }
  const writeErrno: number = bridge.writeTextAtomic(absolute, text);
  if ((!(writeErrno === 0))) {
    return writeError(bridge, label, "cannot write", relative, writeErrno);
  }
  return executeEffects(bridge, root, outcome, (index + 1));
}

function executeEffects(bridge: any, root: string, outcome: driver.TagCommandOutcome, index: number): number {
  if ((index >= outcome.effects.length)) {
    return outcome.status;
  }
  const matched139 = outcome.effects[index];
  switch (matched139._tag) {
    case "CommandStdout": {
      const text = matched139.text;
      bridge.out(text);
      return executeEffects(bridge, root, outcome, (index + 1));
    }
    case "CommandStderr": {
      const text = matched139.text;
      bridge.err(text);
      return executeEffects(bridge, root, outcome, (index + 1));
    }
    case "CommandWrite": {
      const relative = matched139.path;
      const text = matched139.text;
      const makeParents = matched139.makeParents;
      const label = matched139.label;
      return executeWrite(bridge, root, outcome, index, relative, text, makeParents, label);
    }
    case "CommandEditFacts": {
      const relative = matched139.path;
      const remove = matched139.remove;
      const add = matched139.add;
      const label = matched139.label;
      const result: any = bridge.editHostFacts(path(root, relative), remove, add);
      if ((bridge.status(result) === 0)) {
        return executeEffects(bridge, root, outcome, (index + 1));
      }
      return emitIoError(bridge, ("" + label + ": cannot edit '" + relative + "': " + bridge.moduleFactsMessage(result) + "\n"));
    }
  }
}

function runWithModules(bridge: any, root: string, action: driver.TagCommandAction, modules: r.ModuleTags[]): number {
  const matched140 = loadActionHosts(bridge, root, action);
  switch (matched140._tag) {
    case "HostDocumentsLoadRejected": {
      const message = matched140.message;
      return emitIoError(bridge, message);
    }
    case "HostDocumentsLoaded": {
      const documents = matched140.documents;
      return executeEffects(bridge, root, driver.runTagCommand(driver.makeTagCommandRepository(modules, documents), action), 0);
    }
  }
}

function runLoadedAction(bridge: any, root: string, action: driver.TagCommandAction): number {
  if (driver.actionNeedsModules(action)) {
    const matched141 = repository.loadModules(bridge, root);
    switch (matched141._tag) {
      case "ModulesRejected": {
        const message = matched141.message;
        return emitIoError(bridge, message);
      }
      case "ModulesLoaded": {
        const modules = matched141.modules;
        return runWithModules(bridge, root, action, modules);
      }
    }
  }
  return runWithModules(bridge, root, action, []);
}

function runAction(bridge: any, root: string, action: driver.TagCommandAction): number {
  const matched142 = driver.preloadTagCommand(action);
  switch (matched142._tag) {
    case "TagCommandRefusal": {
      const outcome = matched142.outcome;
      return executeEffects(bridge, root, outcome, 0);
    }
    case "TagCommandLoad": {
      const token = matched142.token;
      return runLoadedAction(bridge, root, action);
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
  bridge.err(("" + "Usage: firn tag <list|show|filter|index|status|enable|disable|" + "opt-in|opt-out> [<leaf>]\n" + "       firn module <enable|disable> <name>\n"));
  return 64;
}

export function run(bridge: any, args: string[]): number {
  const matched143 = driver.parseTagCommandArgv(args, defaultHost(bridge));
  switch (matched143._tag) {
    case "OtherTagCommand": {
      const argv = matched143.argv;
      return usageError(bridge);
    }
    case "InvalidTagCommand": {
      const argv = matched143.argv;
      return usageError(bridge);
    }
    case "ParsedTagCommand": {
      const action = matched143.action;
      const root: string | null = repositoryRoot(bridge);
      if ((root === null)) {
        bridge.err("firn: FIRN_REPO and HOME are not set\n");
        return 1;
      }
      return runAction(bridge, root, action);
    }
  }
}
