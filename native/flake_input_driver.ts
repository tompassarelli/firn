import * as input from './flake_input.ts';
export type FlakeInputArgv = { _tag: "ParsedFlakeInputEmit"; token: boolean }
  | { _tag: "OtherFirnCommand"; argv: string[] }
  | { _tag: "InvalidFlakeInputArgv"; argv: string[] };

export function parseFlakeInputArgv(argv: string[]): FlakeInputArgv {
  if (((argv.length >= 2) && (argv[0] === "flake-input") && (argv[1] === "resolve"))) {
    if (((argv.length === 3) && (argv[2] === "emit"))) {
      return { _tag: "ParsedFlakeInputEmit" as const, token: false };
    }
    return { _tag: "InvalidFlakeInputArgv" as const, argv: argv };
  }
  return { _tag: "OtherFirnCommand" as const, argv: argv };
}

export function inputsFromRows(rows: string[][]): input.FlakeInput[] {
  let index: number = 0;
  let declared: input.FlakeInput[] = [];
  while (true) {
    if ((index >= rows.length)) {
      return input.collect(declared);
    }
    const row: string[] = rows[index];
    [index, declared] = [(index + 1), [...declared, input.makeFlakeInput(row[1], row[0], row[2])]];
    continue;
  }
}

function sourceModuleLines(inputs: input.FlakeInput[], names: string[], index: number): string {
  if ((index >= names.length)) {
    return "";
  }
  const name: string = names[index];
  return ("" + "  " + name + " (from " + input.findInput(inputs, name).sourceModule + ")\n" + sourceModuleLines(inputs, names, (index + 1)));
}

function pluralSuffix(count: number): string {
  if ((count === 1)) {
    return "";
  }
  return "s";
}

export function summaryText(inputs: input.FlakeInput[], changed: boolean): string {
  const inputCount: number = inputs.length;
  const moduleCount: number = input.sourceModuleCount(inputs);
  return ("" + ((inputCount === 0) ? "flake-inputs: no module inputs found\n" : ("" + "flake-inputs: " + inputCount + " module input" + pluralSuffix(inputCount) + " from " + moduleCount + " module" + pluralSuffix(moduleCount) + "\n" + sourceModuleLines(inputs, input.sortedInputNames(inputs), 0))) + (changed ? "flake-inputs: updated flake.nix\n" : "flake-inputs: flake.nix is up to date\n"));
}
