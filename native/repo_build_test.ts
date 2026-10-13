import { isDeepStrictEqual } from 'node:util';
import * as build from './repo_build.ts';

function expect(seed: number, condition: boolean, message: string): number {
  if (condition) {
    return 0;
  }
  return 1;
}

function testPathContract(seed: number): number {
  return expect(seed, (build.sourcePath("flake.gal") && build.sourcePath(("" + "modules/alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "/default.gal")) && (!build.sourcePath("scripts/fixture.gal")) && (!build.sourcePath("tests/fixture.gal")) && (!build.sourcePath("docs/fixtures/example.gal")) && (!build.sourcePath(("" + "modules/alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "/default.bnix"))) && (!build.sourcePath("result-old/module.gal")) && (!build.sourcePath(".direnv/cache/module.gal")) && build.obsoleteOutputPath(("" + "hosts/alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "/enabled-tags.nix")) && isDeepStrictEqual(build.outputRelative(("" + "modules/alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "/default.gal")), ("" + "modules/alpha" + (isDeepStrictEqual(seed, 0) ? "" : seed) + "/default.nix"))), "source inventory path contract");
}

function testCommandContract(seed: number): number {
  return expect(seed, ((build.parseRepoBuildArgv(["repo", "build"])._tag === "ParsedRepoBuild") && (build.parseRepoBuildArgv(["repo", "build", "all"])._tag === "ParsedRepoBuild") && (build.parseRepoBuildArgv(["repo", "build", "host"])._tag === "InvalidRepoBuildArgv") && (build.parseRepoBuildArgv(["repo", "validate"])._tag === "OtherRepoBuildCommand")), "repo build argv contract");
}

export function runScenarios(): number {
  if ((isDeepStrictEqual(testPathContract(0), 0) && isDeepStrictEqual(testCommandContract(0), 0))) {
    return 0;
  }
  console.log("FAIL repo_build scenarios");
  return 1;
}
