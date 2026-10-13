import { isDeepStrictEqual } from 'node:util';
import * as r from './tag_resolve.ts';
import * as c from './tag_commands.ts';
import * as d from './tag_commands_driver.ts';
import * as p from './tag_resolve_property_test.ts';

function without(values: string[], value: string): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= values.length)) {
      return result;
    }
    [index, result] = [(index + 1), (isDeepStrictEqual(value, values[index]) ? result : [...result, values[index]])];
    continue;
  }
}

function facts(host: r.HostTags): string[] {
  const name: string = host.host;
  return (() => {
    let index: number = 0;
    let result: string[] = [];
    while (true) {
      if ((index >= host.enabled.length)) {
        let d: number = 0;
        let out: string[] = result;
        while (true) {
          if ((d >= host.disabled.length)) {
            return out;
          }
          [d, out] = [(d + 1), [...out, c.disablesFact(name, host.disabled[d])]];
          continue;
        }
      }
      const entry: r.EnabledTag = host.enabled[index];
      [index, result] = [(index + 1), [...[...result, c.enablesFact(name, entry.tag)], ...c.editFacts(name, entry)]];
      continue;
    }
  })().slice().sort();
}

function minus(left: string[], right: string[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= left.length)) {
      return result;
    }
    [index, result] = [(index + 1), (p.member(right, left[index]) ? result : [...result, left[index]])];
    continue;
  }
}

function commandArgv(op: number, tag: string, module: string): string[] {
  if (isDeepStrictEqual(op, 0)) {
    return ["tag", "enable", tag];
  }else if (isDeepStrictEqual(op, 1)) {
    return ["tag", "disable", tag];
  }else if (isDeepStrictEqual(op, 2)) {
    return ["tag", "opt-in", ("" + tag + "+" + module)];
  }else if (isDeepStrictEqual(op, 3)) {
    return ["tag", "opt-out", ("" + tag + "+" + module)];
  }else if (isDeepStrictEqual(op, 4)) {
    return ["module", "disable", module];
  }else {
    return ["module", "enable", module];
  }
}

function changedHost(host: r.HostTags, op: number, tag: string, module: string): r.HostTags {
  const enabled: r.EnabledTag[] = host.enabled;
  const present: boolean = (() => {
    let index: number = 0;
    while (true) {
      if ((index >= enabled.length)) {
        return false;
      }
      if (isDeepStrictEqual(tag, enabled[index].tag)) {
        return true;
      }
      index = (index + 1);
      continue;
    }
  })();
  const nextEnabled: r.EnabledTag[] = (() => {
    let index: number = 0;
    let result: r.EnabledTag[] = [];
    while (true) {
      if ((index >= enabled.length)) {
        if (((!present) && (isDeepStrictEqual(op, 0) || isDeepStrictEqual(op, 2) || isDeepStrictEqual(op, 3)))) {
          return [...result, r.makeEnabledTag(tag, (isDeepStrictEqual(op, 2) ? [module] : []), (isDeepStrictEqual(op, 3) ? [module] : []))];
        }
        return result;
      }
      const entry: r.EnabledTag = enabled[index];
      [index, result] = [(index + 1), ((!isDeepStrictEqual(tag, entry.tag)) ? [...result, entry] : (isDeepStrictEqual(op, 1) ? result : [...result, r.makeEnabledTag(tag, ((isDeepStrictEqual(op, 2) && (!p.member(entry.pluses, module))) ? [...entry.pluses, module] : entry.pluses), ((isDeepStrictEqual(op, 3) && (!p.member(entry.minuses, module))) ? [...entry.minuses, module] : entry.minuses))]))];
      continue;
    }
  })();
  return r.makeHostTags("fixture", nextEnabled, (() => {
    if (isDeepStrictEqual(op, 4)) {
      if (p.member(host.disabled, module)) {
        return host.disabled;
      }
      return [...host.disabled, module].slice().sort();
    }else if (isDeepStrictEqual(op, 5)) {
      return without(host.disabled, module);
    }else {
      return host.disabled;
    }
  })(), host.platform, host.restrictAllowed, host.allowed);
}

function edits(outcome: d.TagCommandOutcome): string[][] {
  let index: number = 0;
  let result: string[][] = [[], []];
  while (true) {
    if ((index >= outcome.effects.length)) {
      return result;
    }
    const matched151 = outcome.effects[index];
    switch (matched151._tag) {
      case "CommandEditFacts": {
        const path = matched151.path;
        const remove = matched151.remove;
        const add = matched151.add;
        const label = matched151.label;
        [index, result] = [(index + 1), [[...result[0], ...remove].slice().sort(), [...result[1], ...add].slice().sort()]];
        continue;
      }
      case "CommandWrite": {
        const path = matched151.path;
        const value = matched151.text;
        const parents = matched151.makeParents;
        const label = matched151.label;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "CommandStdout": {
        const value = matched151.text;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "CommandStderr": {
        const value = matched151.text;
        [index, result] = [(index + 1), result];
        continue;
      }
    }
  }
}

function noWrite(outcome: d.TagCommandOutcome): boolean {
  return ((!p.member(d.outcomeEffectKinds(outcome), "write")) && (!p.member(d.outcomeEffectKinds(outcome), "edit")));
}

function checkOp(catalog: r.ModuleTags[], host: r.HostTags, document: c.HostDocument, op: number, tag: string, module: string): boolean {
  const matched152 = d.parseTagCommandArgv(commandArgv(op, tag, module), "fixture");
  switch (matched152._tag) {
    case "OtherTagCommand": {
      const argv = matched152.argv;
      return false;
    }
    case "InvalidTagCommand": {
      const argv = matched152.argv;
      return false;
    }
    case "ParsedTagCommand": {
      const command = matched152.action;
      const outcome: d.TagCommandOutcome = d.runTagCommand(d.makeTagCommandRepository(catalog, [document]), command);
      const expected: r.HostTags = changedHost(host, op, tag, module);
      const before: string[] = facts(host);
      const after: string[] = facts(expected);
      const refused: boolean = (isDeepStrictEqual(op, 5) && (!p.member(host.disabled, module)));
      const second: d.TagCommandOutcome = d.runTagCommand(d.makeTagCommandRepository(catalog, [c.makeHostDocument(expected, [])]), command);
      return (isDeepStrictEqual(outcome.status, (refused ? 1 : 0)) && ((!refused) || noWrite(outcome)) && isDeepStrictEqual(edits(outcome), [minus(before, after), minus(after, before)]) && noWrite(second) && isDeepStrictEqual(second.status, (isDeepStrictEqual(op, 5) ? 1 : 0)) && isDeepStrictEqual(p.model(catalog, expected), r.resolve(catalog, expected).active));
    }
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
    const host: r.HostTags = p.host(seed);
    const catalog: r.ModuleTags[] = p.modules(seed);
    const document: c.HostDocument = c.makeHostDocument(host, []);
    const repository: d.TagCommandRepository = d.makeTagCommandRepository(catalog, [document]);
    const malformed: d.TagCommandOutcome = d.runTagCommand(repository, { _tag: "TagOptIn" as const, host: "fixture", leaf: "desktop-epsilon" });
    const missing: d.TagCommandOutcome = d.runTagCommand(repository, { _tag: "TagEnable" as const, host: "missing", tag: "desktop" });
    const passed: boolean = (isDeepStrictEqual(malformed.status, 1) && noWrite(malformed) && isDeepStrictEqual(missing.status, 1) && noWrite(missing) && (() => {
      let op: number = 0;
      while (true) {
        if ((op >= 6)) {
          return true;
        }
        if (checkOp(catalog, host, document, op, p.tags[(seed % 3)], p.names[(seed % 5)])) {
          op = (op + 1);
          continue;
        }
        console.log(("" + "FAIL mutation seed=" + seed + " op=" + op));
        return false;
      }
    })());
    if (passed) {
      [index, seed] = [(index + 1), p.nextSeed(seed)];
      continue;
    }
    console.log(("" + "FAIL mutation seed=" + seed + " case=" + index));
    return 1;
  }
}
