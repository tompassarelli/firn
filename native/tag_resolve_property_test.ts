import { isDeepStrictEqual } from 'node:util';
import * as r from './tag_resolve.ts';

export function nextSeed(seed: number): number {
  return ((seed * 48271) % 2147483647);
}

export function member(values: string[], value: string): boolean {
  let index: number = 0;
  while (true) {
    if ((index >= values.length)) {
      return false;
    }
    if (isDeepStrictEqual(value, values[index])) {
      return true;
    }
    index = (index + 1);
    continue;
  }
}

export function subset(seed: number, values: string[]): string[] {
  let index: number = 0;
  let state: number = seed;
  let result: string[] = [];
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, state, result] = [(index + 1), nextSeed(state), (isDeepStrictEqual((state % 3), 0) ? result : [...result, values[index]])];
    continue;
  }
}
export const names: string[] = ["alpha", "beta", "delta", "epsilon", "gamma"];
export const tags: string[] = ["desktop", "terminal", "creative"];

export function modules(seed: number): r.ModuleTags[] {
  let index: number = 0;
  let state: number = seed;
  let result: r.ModuleTags[] = [];
  while (true) {
    if ((index >= names.length)) {
      return result;
    }
    [index, state, result] = [(index + 1), nextSeed(state), [...result, r.makeModuleTags(names[index], subset(state, tags), subset(nextSeed(state), tags), [])]];
    continue;
  }
}

export function host(seed: number): r.HostTags {
  const enabled: string[] = subset(seed, (isDeepStrictEqual((seed % 2), 0) ? ["unknown", "creative", "desktop", "terminal"] : ["terminal", "desktop", "creative", "unknown"]));
  return r.makeHostTags("fixture", (() => {
    let index: number = 0;
    let state: number = nextSeed(seed);
    let result: r.EnabledTag[] = [];
    while (true) {
      if ((index >= enabled.length)) {
        return result;
      }
      [index, state, result] = [(index + 1), nextSeed(state), [...result, r.makeEnabledTag(enabled[index], subset(state, [...names, "absent"]), subset(nextSeed(state), [...names, "absent"]))]];
      continue;
    }
  })(), subset(nextSeed(nextSeed(seed)), [...names, "absent"]), (isDeepStrictEqual((seed % 2), 0) ? "linux" : "darwin"), isDeepStrictEqual((seed % 2), 1), subset(nextSeed(seed), names));
}

export function contributes(module: r.ModuleTags, entry: r.EnabledTag): boolean {
  return ((member(module.tags, entry.tag) && (!member(entry.minuses, module.name))) || (member(module.optIn, entry.tag) && member(entry.pluses, module.name)));
}

export function model(catalog: r.ModuleTags[], host: r.HostTags): string[] {
  let index: number = 0;
  let active: string[] = [];
  while (true) {
    if ((index >= catalog.length)) {
      return active.slice().sort();
    }
    const module: r.ModuleTags = catalog[index];
    const name: string = module.name;
    const selected: boolean = (() => {
      let tagIndex: number = 0;
      while (true) {
        if ((tagIndex >= host.enabled.length)) {
          return false;
        }
        if (contributes(module, host.enabled[tagIndex])) {
          return true;
        }
        tagIndex = (tagIndex + 1);
        continue;
      }
    })();
    [index, active] = [(index + 1), ((selected && (!member(host.disabled, name)) && ((!host.restrictAllowed) || member(host.allowed, name))) ? [...active, name] : active)];
    continue;
  }
}

function declared(catalog: r.ModuleTags[], tag: string, optIn: boolean): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= catalog.length)) {
      return result;
    }
    const module: r.ModuleTags = catalog[index];
    [index, result] = [(index + 1), (member((optIn ? module.optIn : module.tags), tag) ? [...result, module.name] : result)];
    continue;
  }
}

function missingCount(values: string[], known: string[]): number {
  let index: number = 0;
  let total: number = 0;
  while (true) {
    if ((index >= values.length)) {
      return total;
    }
    [index, total] = [(index + 1), (total + (member(known, values[index]) ? 0 : 1))];
    continue;
  }
}

function diagnostics(catalog: r.ModuleTags[], host: r.HostTags, result: r.Resolution): boolean {
  let index: number = 0;
  let errors: number = missingCount(host.disabled, names);
  let warnings: number = 0;
  while (true) {
    if ((index >= host.enabled.length)) {
      return (isDeepStrictEqual(errors, result.errors.length) && isDeepStrictEqual(warnings, result.warnings.length));
    }
    const entry: r.EnabledTag = host.enabled[index];
    const defaults: string[] = declared(catalog, entry.tag, false);
    const optIns: string[] = declared(catalog, entry.tag, true);
    [index, errors, warnings] = [(index + 1), (errors + ((isDeepStrictEqual((defaults.length + optIns.length), 0) ? 1 : 0) + missingCount(entry.pluses, optIns))), (warnings + missingCount(entry.minuses, defaults))];
    continue;
  }
}

export function runProperties(samples: number): number {
  if ((samples <= 0)) {
    return 1;
  }
  let index: number = 0;
  let seed: number = 73421;
  while (true) {
    if ((index >= samples)) {
      return 0;
    }
    const catalog: r.ModuleTags[] = modules(seed);
    const config: r.HostTags = host(seed);
    const result: r.Resolution = r.resolve(catalog, config);
    if ((isDeepStrictEqual(model(catalog, config), result.active) && diagnostics(catalog, config, result))) {
      [index, seed] = [(index + 1), nextSeed(seed)];
      continue;
    }
    console.log(("" + "FAIL tag algebra seed=" + seed + " case=" + index));
    return 1;
  }
}
