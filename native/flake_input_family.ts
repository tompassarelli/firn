import * as driver from './flake_input_driver.ts';
const maxSourceBytes: number = 16777216;

function readFlake(bridge: any, root: string): string {
  const result: any = bridge.readText(("" + root + "/flake.nix"), maxSourceBytes);
  if ((bridge.status(result) === 0)) {
    return bridge.value(result);
  }
  return "";
}

function emitError(bridge: any, message: string): number {
  bridge.err(("" + "firn flake-input resolve: " + message + "\n"));
  return 1;
}

export function runRoot(bridge: any, root: string): number {
  const before: string = readFlake(bridge, root);
  const buildStatus: number = bridge.runFlakeBuild(root);
  if ((!(buildStatus === 0))) {
    return emitError(bridge, ("" + "galileo build of flake.gal exited " + buildStatus));
  }
  const facts: any = bridge.readFlakeInputs(root);
  if ((!(bridge.status(facts) === 0))) {
    return emitError(bridge, ("" + "cannot read flake inputs through galileo query: " + bridge.moduleFactsMessage(facts)));
  }
  bridge.out(driver.summaryText(driver.inputsFromRows(bridge.value(facts)), (!(before === readFlake(bridge, root)))));
  return 0;
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

function usageError(bridge: any): number {
  bridge.err("Usage: firn flake-input resolve emit\n");
  return 64;
}

export function run(bridge: any, args: string[]): number {
  const matched205 = driver.parseFlakeInputArgv(args);
  switch (matched205._tag) {
    case "OtherFirnCommand": {
      const argv = matched205.argv;
      return usageError(bridge);
    }
    case "InvalidFlakeInputArgv": {
      const argv = matched205.argv;
      return usageError(bridge);
    }
    case "ParsedFlakeInputEmit": {
      const token = matched205.token;
      const root: string | null = repositoryRoot(bridge);
      if ((root === null)) {
        bridge.err("firn flake-input resolve: FIRN_REPO and HOME are not set\n");
        return 1;
      }
      return runRoot(bridge, root);
    }
  }
}
