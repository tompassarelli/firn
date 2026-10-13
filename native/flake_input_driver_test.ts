import { isDeepStrictEqual } from 'node:util';
import * as input from './flake_input.ts';
import * as driver from './flake_input_driver.ts';

function parsed(argv: string[]): boolean {
  const matched206 = driver.parseFlakeInputArgv(argv);
  switch (matched206._tag) {
    case "ParsedFlakeInputEmit": {
      const token = matched206.token;
      return true;
    }
    case "OtherFirnCommand": {
      const other = matched206.argv;
      return false;
    }
    case "InvalidFlakeInputArgv": {
      const invalid = matched206.argv;
      return false;
    }
  }
}

function invalid(argv: string[]): boolean {
  const matched207 = driver.parseFlakeInputArgv(argv);
  switch (matched207._tag) {
    case "ParsedFlakeInputEmit": {
      const token = matched207.token;
      return false;
    }
    case "OtherFirnCommand": {
      const other = matched207.argv;
      return false;
    }
    case "InvalidFlakeInputArgv": {
      const invalid = matched207.argv;
      return true;
    }
  }
}

function other(argv: string[]): boolean {
  const matched208 = driver.parseFlakeInputArgv(argv);
  switch (matched208._tag) {
    case "ParsedFlakeInputEmit": {
      const token = matched208.token;
      return false;
    }
    case "OtherFirnCommand": {
      const other = matched208.argv;
      return true;
    }
    case "InvalidFlakeInputArgv": {
      const invalid = matched208.argv;
      return false;
    }
  }
}

function caseArgvGrammar(): boolean {
  return (parsed(["flake-input", "resolve", "emit"]) && invalid(["flake-input", "resolve"]) && invalid(["flake-input", "resolve", "show"]) && invalid(["flake-input", "resolve", "emit", "extra"]) && other(["tag", "resolve", "all"]));
}

function caseSharedInputKeepsFirstModule(): boolean {
  const inputs: input.FlakeInput[] = driver.inputsFromRows([["alpha", "alpha", "github:alpha/project"], ["alpha", "zeta", "github:zeta/project"], ["beta", "zeta", "github:zeta/project"]]);
  return (isDeepStrictEqual(input.sortedInputNames(inputs), ["alpha", "zeta"]) && isDeepStrictEqual(input.findInput(inputs, "zeta").sourceModule, "alpha") && isDeepStrictEqual(input.sourceModuleCount(inputs), 1));
}

export function runScenarios(): number {
  if ((caseArgvGrammar() && caseSharedInputKeepsFirstModule())) {
    return 0;
  }
  console.log("FAIL flake_input_driver scenarios");
  return 1;
}
