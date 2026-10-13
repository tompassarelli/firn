export type SourceState = { relative: string; outputRelative: string };
export function makeSourceState(relative: string, outputRelative: string): SourceState { return { relative, outputRelative }; }
export type SourceInventory = { sources: SourceState[]; obsoleteOutputs: string[] };
export function makeSourceInventory(sources: SourceState[], obsoleteOutputs: string[]): SourceInventory { return { sources, obsoleteOutputs }; }
export type RepoBuildPlan = { sources: SourceState[]; obsoleteOutputs: string[] };
export function makeRepoBuildPlan(sources: SourceState[], obsoleteOutputs: string[]): RepoBuildPlan { return { sources, obsoleteOutputs }; }
export type RepoBuildArgv = { _tag: "ParsedRepoBuild"; token: boolean }
  | { _tag: "ParsedRepoDiff"; target: string }
  | { _tag: "OtherRepoBuildCommand"; argv: string[] }
  | { _tag: "InvalidRepoBuildArgv"; argv: string[] };

export function startsWith(text: string, prefix: string): boolean {
  return ((text.length >= prefix.length) && (text.slice(0, prefix.length) === prefix));
}

function endsWith(text: string, suffix: string): boolean {
  return ((text.length >= suffix.length) && (text.slice((text.length - suffix.length), text.length) === suffix));
}

function rootResultPath(relative: string): boolean {
  return startsWith(relative, "result");
}

export function traversalExcluded(relative: string): boolean {
  return ((relative === ".direnv") || startsWith(relative, ".direnv/") || (relative === ".firn-build") || startsWith(relative, ".firn-build/") || rootResultPath(relative));
}

function sourceExcluded(relative: string): boolean {
  return (traversalExcluded(relative) || (relative === "scripts") || startsWith(relative, "scripts/") || (relative === "tests") || startsWith(relative, "tests/") || (relative === "docs/fixtures") || startsWith(relative, "docs/fixtures/"));
}

export function sourcePath(relative: string): boolean {
  return (endsWith(relative, ".gal") && (!sourceExcluded(relative)));
}

export function obsoleteOutputPath(relative: string): boolean {
  return ((!traversalExcluded(relative)) && ((relative === "enabled-tags.nix") || endsWith(relative, "/enabled-tags.nix")));
}

export function outputRelative(sourceRelative: string): string {
  return ("" + sourceRelative.slice(0, (sourceRelative.length - 4)) + ".nix");
}

export function buildPlan(inventory: SourceInventory): RepoBuildPlan {
  return makeRepoBuildPlan(inventory.sources, inventory.obsoleteOutputs);
}

export function parseRepoBuildArgv(argv: string[]): RepoBuildArgv {
  if (((argv.length >= 2) && (argv[0] === "repo") && (argv[1] === "diff"))) {
    if (((argv.length <= 3) && ((argv.length === 2) || (!startsWith(argv[2], "-"))))) {
      return { _tag: "ParsedRepoDiff" as const, target: ((argv.length === 2) ? "all" : argv[2]) };
    }
    return { _tag: "InvalidRepoBuildArgv" as const, argv: argv };
  }
  if (((argv.length >= 2) && (argv[0] === "repo") && (argv[1] === "build"))) {
    if ((argv.length === 2)) {
      return { _tag: "ParsedRepoBuild" as const, token: true };
    }else if (((argv.length === 3) && (argv[2] === "all"))) {
      return { _tag: "ParsedRepoBuild" as const, token: true };
    }else {
      return { _tag: "InvalidRepoBuildArgv" as const, argv: argv };
    }
  }
  return { _tag: "OtherRepoBuildCommand" as const, argv: argv };
}

export function errnoMessage(operation: string, relative: string, errno: number): string {
  return ("" + "firn-build: " + operation + " '" + relative + "': errno " + errno + "\n");
}
