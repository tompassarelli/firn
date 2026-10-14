import * as build from './repo_build.ts';
import * as tagDriver from './tag_resolve_driver.ts';
import * as tagFamily from './tag_resolve_family.ts';
import * as flakeFamily from './flake_input_family.ts';
const maxDirectoryEntries: number = 16384;
const maxParserOutputBytes: number = 16777216;
type InventoryLoadResult = { _tag: "InventoryLoaded"; inventory: build.SourceInventory }
  | { _tag: "InventoryRejected"; message: string };

function relativeChild(parent: string, name: string): string {
  if ((parent === "")) {
    return name;
  }
  return ("" + parent + "/" + name);
}

function absolutePath(root: string, relative: string): string {
  return ("" + root + "/" + relative);
}

function mergeInventory(left: build.SourceInventory, right: build.SourceInventory): build.SourceInventory {
  return build.makeSourceInventory([...left.sources, ...right.sources], [...left.obsoleteOutputs, ...right.obsoleteOutputs]);
}

function loadInventoryDirectory(bridge: any, root: string, relative: string): InventoryLoadResult {
  const absolute: string = ((relative === "") ? root : absolutePath(root, relative));
  const listResult: any = bridge.listDirectory(absolute, maxDirectoryEntries);
  const listErrno: number = bridge.status(listResult);
  if ((!(listErrno === 0))) {
    return { _tag: "InventoryRejected" as const, message: build.errnoMessage("cannot list", ((relative === "") ? "." : relative), listErrno) };
  }
  const names: string[] = bridge.value(listResult).slice().sort();
  let index: number = 0;
  let inventory: build.SourceInventory = build.makeSourceInventory([], []);
  while (true) {
    if ((index >= names.length)) {
      return { _tag: "InventoryLoaded" as const, inventory: inventory };
    }
    const entryRelative: string = relativeChild(relative, names[index]);
    const kindResult: any = bridge.pathKind(absolutePath(root, entryRelative));
    const kindErrno: number = bridge.status(kindResult);
    if ((!(kindErrno === 0))) {
      if ((kindErrno === 2)) {
        [index, inventory] = [(index + 1), inventory];
        continue;
      }
      return { _tag: "InventoryRejected" as const, message: build.errnoMessage("cannot inspect", entryRelative, kindErrno) };
    }
    const kind: number = bridge.value(kindResult);
    if (((kind === 2) && (!build.traversalExcluded(entryRelative)))) {
      const matched193 = loadInventoryDirectory(bridge, root, entryRelative);
      switch (matched193._tag) {
        case "InventoryRejected": {
          const message = matched193.message;
          return { _tag: "InventoryRejected" as const, message: message };
        }
        case "InventoryLoaded": {
          const childInventory = matched193.inventory;
          [index, inventory] = [(index + 1), mergeInventory(inventory, childInventory)];
          continue;
        }
      }
    }else if ((((kind === 1) || (kind === 3)) && build.sourcePath(entryRelative))) {
      [index, inventory] = [(index + 1), mergeInventory(inventory, build.makeSourceInventory([build.makeSourceState(entryRelative, build.outputRelative(entryRelative))], []))];
      continue;
    }else if ((((kind === 1) || (kind === 3)) && build.obsoleteOutputPath(entryRelative))) {
      [index, inventory] = [(index + 1), mergeInventory(inventory, build.makeSourceInventory([], [entryRelative]))];
      continue;
    }else {
      [index, inventory] = [(index + 1), inventory];
      continue;
    }
  }
}

function emitError(bridge: any, message: string): number {
  bridge.err(message);
  return 1;
}

function runPreparation(bridge: any, root: string): number {
  const matched194 = tagFamily.directoryNames(bridge, root, "hosts");
  switch (matched194._tag) {
    case "DirectoryNamesRejected": {
      const message = matched194.message;
      bridge.err(message);
      return emitError(bridge, "firn-build: tag resolution failed; aborting before .nix regeneration\n");
    }
    case "DirectoryNamesLoaded": {
      const names = matched194.names;
      const tagStatus: number = tagFamily.runAction(bridge, root, names, { _tag: "ResolveAll" as const, emit: true });
      if ((!(tagStatus === 0))) {
        return emitError(bridge, "firn-build: tag resolution failed; aborting before .nix regeneration\n");
      }
      const flakeStatus: number = flakeFamily.runRoot(bridge, root);
      if ((flakeStatus === 0)) {
        return 0;
      }
      return emitError(bridge, "firn-build: flake-inputs resolution failed; aborting\n");
    }
  }
}

function emitParserOutput(bridge: any, stdout: string, stderr: string): number {
  ((stdout === "") ? 0 : (() => {
    bridge.out(stdout);
    return 0;
  })());
  ((stderr === "") ? 0 : (() => {
    bridge.err(stderr);
    return 0;
  })());
  return 0;
}

function runNixCheck(bridge: any, root: string, paths: string[]): number {
  const capture = bridge.runCapture(['env', '-C', root, 'nix-instantiate', '--parse', ...paths], maxParserOutputBytes);
  if (bridge.status(capture) !== 0) return emitError(bridge, `firn-build: cannot start Nix parser: errno ${bridge.status(capture)}\n`);
  const result = bridge.value(capture);
  if (bridge.exitStatus(result) !== 0) emitParserOutput(bridge, bridge.stdout(result), bridge.stderr(result));
  return bridge.exitStatus(result);
}

function executePlan(bridge: any, root: string, plan: build.RepoBuildPlan): number {
  const sources: build.SourceState[] = plan.sources;
  const parseStatus = sources.length === 0 ? 0 : runNixCheck(bridge, root, sources.map(source => source.relative));
  if (parseStatus !== 0) return parseStatus;
  ((sources.length === 0) ? bridge.out("firn-build: nothing to rebuild.\n") : 0);
  return 0;
}

function diffSelected(state: build.SourceState, target: string): boolean {
  return ((target === "all") || (target === state.relative) || (target === state.outputRelative) || build.startsWith(state.relative, ("" + target + "/")));
}

function runDiff(bridge: any, root: string, target: string): number {
  const matched195 = loadInventoryDirectory(bridge, root, "");
  switch (matched195._tag) {
    case "InventoryRejected": {
      const message = matched195.message;
      return emitError(bridge, message);
    }
    case "InventoryLoaded": {
      const inventory = matched195.inventory;
      const sources: build.SourceState[] = inventory.sources;
      const selected: string[] = (() => {
        let index: number = 0;
        let paths: string[] = [];
        while (true) {
          if ((index >= sources.length)) {
            return paths;
          }
          const state: build.SourceState = sources[index];
          [index, paths] = [(index + 1), (diffSelected(state, target) ? [...paths, state.relative] : paths)];
          continue;
        }
      })();
      if ((selected.length === 0)) {
        bridge.out("firn diff: 0 checked\n");
        return 1;
      }
      const status: number = runNixCheck(bridge, root, selected);
      bridge.out(("" + "firn diff: " + selected.length + " checked, " + ((status === 0) ? "clean" : "differing or failed") + "\n"));
      return status;
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

function runRoot(bridge: any, root: string): number {
  const preparationStatus: number = runPreparation(bridge, root);
  if ((!(preparationStatus === 0))) {
    return preparationStatus;
  }
  const matched197 = loadInventoryDirectory(bridge, root, "");
  switch (matched197._tag) {
    case "InventoryRejected": {
      const message = matched197.message;
      return emitError(bridge, message);
    }
    case "InventoryLoaded": {
      const inventory = matched197.inventory;
      return executePlan(bridge, root, build.buildPlan(inventory));
    }
  }
}

function runCommand(bridge: any, root: string): number {
  bridge.out(">> firn-build\n");
  const status: number = runRoot(bridge, root);
  if ((status === 0)) {
    return 0;
  }
  bridge.err("firn repo build: failed.\n");
  return 1;
}

function usageError(bridge: any): number {
  bridge.err("Usage: firn repo build [all] | firn repo diff [target|all]\n");
  return 64;
}

export function run(bridge: any, args: string[]): number {
  const matched198 = build.parseRepoBuildArgv(args);
  switch (matched198._tag) {
    case "OtherRepoBuildCommand": {
      const argv = matched198.argv;
      return usageError(bridge);
    }
    case "InvalidRepoBuildArgv": {
      const argv = matched198.argv;
      return usageError(bridge);
    }
    case "ParsedRepoDiff": {
      const target = matched198.target;
      const root: string | null = repositoryRoot(bridge);
      if ((root === null)) {
        return emitError(bridge, "firn diff: FIRN_REPO and HOME are not set\n");
      }
      return runDiff(bridge, root, target);
    }
    case "ParsedRepoBuild": {
      const token = matched198.token;
      const root: string | null = repositoryRoot(bridge);
      if ((root === null)) {
        return emitError(bridge, "firn repo build: FIRN_REPO and HOME are not set\n");
      }
      return runCommand(bridge, root);
    }
  }
}
