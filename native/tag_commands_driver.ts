import * as r from './tag_resolve.ts';
import * as c from './tag_commands.ts';
export type TagCommandAction = { _tag: "TagList"; token: boolean }
  | { _tag: "TagShow"; module: string }
  | { _tag: "TagFilter"; tag: string }
  | { _tag: "TagIndex"; stdout: boolean }
  | { _tag: "TagStatus"; host: string }
  | { _tag: "TagEnable"; host: string; tag: string }
  | { _tag: "TagDisable"; host: string; tag: string }
  | { _tag: "TagOptIn"; host: string; leaf: string }
  | { _tag: "TagOptOut"; host: string; leaf: string }
  | { _tag: "ModuleEnable"; host: string; module: string }
  | { _tag: "ModuleDisable"; host: string; module: string };
export type TagCommandArgv = { _tag: "ParsedTagCommand"; action: TagCommandAction }
  | { _tag: "OtherTagCommand"; argv: string[] }
  | { _tag: "InvalidTagCommand"; argv: string[] };
export type TagCommandRepository = { modules: r.ModuleTags[]; hosts: c.HostDocument[] };
export function makeTagCommandRepository(modules: r.ModuleTags[], hosts: c.HostDocument[]): TagCommandRepository { return { modules, hosts }; }
export type TagCommandHostLookup = { _tag: "TagCommandHostFound"; document: c.HostDocument }
  | { _tag: "TagCommandHostMissing"; host: string };
export type TagCommandEffect = { _tag: "CommandStdout"; text: string }
  | { _tag: "CommandStderr"; text: string }
  | { _tag: "CommandWrite"; path: string; text: string; makeParents: boolean; label: string }
  | { _tag: "CommandEditFacts"; path: string; remove: string[]; add: string[]; label: string };
export type TagCommandOutcome = { status: number; effects: TagCommandEffect[] };
export function makeTagCommandOutcome(status: number, effects: TagCommandEffect[]): TagCommandOutcome { return { status, effects }; }
export type TagCommandPreload = { _tag: "TagCommandLoad"; token: boolean }
  | { _tag: "TagCommandRefusal"; outcome: TagCommandOutcome };

export function parsed(action: TagCommandAction): TagCommandArgv {
  return { _tag: "ParsedTagCommand" as const, action: action };
}

export function invalid(argv: string[]): TagCommandArgv {
  return { _tag: "InvalidTagCommand" as const, argv: argv };
}

export function parseTagAction(argv: string[], defaultHost: string): TagCommandArgv {
  const edge: string = argv[1];
  const arity: number = argv.length;
  if ((edge === "list")) {
    if (((arity === 2) || (arity === 3))) {
      return parsed({ _tag: "TagList" as const, token: false });
    }
    return invalid(argv);
  }else if ((edge === "show")) {
    if ((arity === 3)) {
      return parsed({ _tag: "TagShow" as const, module: argv[2] });
    }
    return invalid(argv);
  }else if ((edge === "filter")) {
    if ((arity === 3)) {
      return parsed({ _tag: "TagFilter" as const, tag: argv[2] });
    }
    return invalid(argv);
  }else if ((edge === "index")) {
    if ((arity === 2)) {
      return parsed({ _tag: "TagIndex" as const, stdout: false });
    }else if ((arity === 3)) {
      return parsed({ _tag: "TagIndex" as const, stdout: ("stdout" === argv[2]) });
    }else {
      return invalid(argv);
    }
  }else if ((edge === "status")) {
    if ((arity === 2)) {
      return parsed({ _tag: "TagStatus" as const, host: defaultHost });
    }else if ((arity === 3)) {
      const leaf: string = argv[2];
      return parsed({ _tag: "TagStatus" as const, host: (((leaf === "current") || (leaf === "all")) ? defaultHost : leaf) });
    }else {
      return invalid(argv);
    }
  }else if ((edge === "enable")) {
    if ((arity === 3)) {
      return parsed({ _tag: "TagEnable" as const, host: defaultHost, tag: argv[2] });
    }
    return invalid(argv);
  }else if ((edge === "disable")) {
    if ((arity === 3)) {
      return parsed({ _tag: "TagDisable" as const, host: defaultHost, tag: argv[2] });
    }
    return invalid(argv);
  }else if ((edge === "opt-in")) {
    if ((arity === 3)) {
      return parsed({ _tag: "TagOptIn" as const, host: defaultHost, leaf: argv[2] });
    }
    return invalid(argv);
  }else if ((edge === "opt-out")) {
    if ((arity === 3)) {
      return parsed({ _tag: "TagOptOut" as const, host: defaultHost, leaf: argv[2] });
    }
    return invalid(argv);
  }else {
    return invalid(argv);
  }
}

export function parseModuleAction(argv: string[], defaultHost: string): TagCommandArgv {
  if ((3 !== argv.length)) {
    return invalid(argv);
  }
  const edge: string = argv[1];
  const module: string = argv[2];
  if ((edge === "enable")) {
    return parsed({ _tag: "ModuleEnable" as const, host: defaultHost, module: module });
  }else if ((edge === "disable")) {
    return parsed({ _tag: "ModuleDisable" as const, host: defaultHost, module: module });
  }else {
    return invalid(argv);
  }
}

export function parseTagCommandArgv(argv: string[], defaultHost: string): TagCommandArgv {
  if ((argv.length < 2)) {
    return { _tag: "OtherTagCommand" as const, argv: argv };
  }
  const node: string = argv[0];
  if ((node === "tag")) {
    return parseTagAction(argv, defaultHost);
  }else if ((node === "module")) {
    return parseModuleAction(argv, defaultHost);
  }else {
    return { _tag: "OtherTagCommand" as const, argv: argv };
  }
}

export function actionNeedsModules(action: TagCommandAction): boolean {
  const matched117 = action;
  switch (matched117._tag) {
    case "TagList": {
      const token = matched117.token;
      return true;
    }
    case "TagShow": {
      const module = matched117.module;
      return true;
    }
    case "TagFilter": {
      const tag = matched117.tag;
      return true;
    }
    case "TagIndex": {
      const stdout = matched117.stdout;
      return true;
    }
    case "TagStatus": {
      const host = matched117.host;
      return true;
    }
    case "TagEnable": {
      const host = matched117.host;
      const tag = matched117.tag;
      return false;
    }
    case "TagDisable": {
      const host = matched117.host;
      const tag = matched117.tag;
      return false;
    }
    case "TagOptIn": {
      const host = matched117.host;
      const leaf = matched117.leaf;
      return false;
    }
    case "TagOptOut": {
      const host = matched117.host;
      const leaf = matched117.leaf;
      return false;
    }
    case "ModuleEnable": {
      const host = matched117.host;
      const module = matched117.module;
      return false;
    }
    case "ModuleDisable": {
      const host = matched117.host;
      const module = matched117.module;
      return false;
    }
  }
}

export function actionHost(action: TagCommandAction): string | null {
  const matched118 = action;
  switch (matched118._tag) {
    case "TagList": {
      const token = matched118.token;
      return null;
    }
    case "TagShow": {
      const module = matched118.module;
      return null;
    }
    case "TagFilter": {
      const tag = matched118.tag;
      return null;
    }
    case "TagIndex": {
      const stdout = matched118.stdout;
      return null;
    }
    case "TagStatus": {
      const host = matched118.host;
      return host;
    }
    case "TagEnable": {
      const host = matched118.host;
      const tag = matched118.tag;
      return host;
    }
    case "TagDisable": {
      const host = matched118.host;
      const tag = matched118.tag;
      return host;
    }
    case "TagOptIn": {
      const host = matched118.host;
      const leaf = matched118.leaf;
      return host;
    }
    case "TagOptOut": {
      const host = matched118.host;
      const leaf = matched118.leaf;
      return host;
    }
    case "ModuleEnable": {
      const host = matched118.host;
      const module = matched118.module;
      return host;
    }
    case "ModuleDisable": {
      const host = matched118.host;
      const module = matched118.module;
      return host;
    }
  }
}

export function findHost(repository: TagCommandRepository, host: string): TagCommandHostLookup {
  let index: number = 0;
  while (true) {
    if ((index >= repository.hosts.length)) {
      return { _tag: "TagCommandHostMissing" as const, host: host };
    }
    const document: c.HostDocument = repository.hosts[index];
    if ((host === document.tags.host)) {
      return { _tag: "TagCommandHostFound" as const, document: document };
    }
    index = (index + 1);
    continue;
  }
}

export function stdoutOutcome(text: string): TagCommandOutcome {
  return makeTagCommandOutcome(0, [{ _tag: "CommandStdout" as const, text: text }]);
}

export function stderrOutcome(status: number, text: string): TagCommandOutcome {
  return makeTagCommandOutcome(status, [{ _tag: "CommandStderr" as const, text: text }]);
}

export function missingStatusOutcome(host: string): TagCommandOutcome {
  return stderrOutcome(1, ("" + "firn tag status: host '" + host + "' is not declared (no '" + host + " is a Host' fact)\n"));
}

export function missingMutationOutcome(host: string): TagCommandOutcome {
  return stderrOutcome(1, ("" + "firn: host '" + host + "' is not declared (no '" + host + " is a Host' fact)\n" + "  (declare it in " + c.hostFactsPath(host) + " first)\n"));
}

export function mutationOutcome(host: string, mutation: c.TagMutation): TagCommandOutcome {
  const relative: string = c.hostFactsPath(host);
  if (mutation.changed) {
    return makeTagCommandOutcome(0, [{ _tag: "CommandEditFacts" as const, path: relative, remove: mutation.remove, add: mutation.add, label: "firn" }, { _tag: "CommandStdout" as const, text: ("" + "updated " + relative + "\n") }]);
  }
  return stdoutOutcome(("" + "no change to " + relative + "\n"));
}

export function malformedTagModuleOutcome(leaf: string): TagCommandOutcome {
  return stderrOutcome(1, ("" + "firn: expected '<tag>+<module>', got '" + leaf + "'\n"));
}

export function preloadTagCommand(action: TagCommandAction): TagCommandPreload {
  const matched120 = action;
  switch (matched120._tag) {
    case "TagOptIn": {
      const host = matched120.host;
      const leaf = matched120.leaf;
      const matched121 = c.splitTagModule(leaf);
      switch (matched121._tag) {
        case "TagModuleRejected": {
          const invalid = matched121.leaf;
          return { _tag: "TagCommandRefusal" as const, outcome: malformedTagModuleOutcome(invalid) };
        }
        case "TagModuleParsed": {
          const tag = matched121.tag;
          const module = matched121.module;
          return { _tag: "TagCommandLoad" as const, token: false };
        }
      }
    }
    case "TagOptOut": {
      const host = matched120.host;
      const leaf = matched120.leaf;
      const matched122 = c.splitTagModule(leaf);
      switch (matched122._tag) {
        case "TagModuleRejected": {
          const invalid = matched122.leaf;
          return { _tag: "TagCommandRefusal" as const, outcome: malformedTagModuleOutcome(invalid) };
        }
        case "TagModuleParsed": {
          const tag = matched122.tag;
          const module = matched122.module;
          return { _tag: "TagCommandLoad" as const, token: false };
        }
      }
    }
    case "TagList": {
      const token = matched120.token;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "TagShow": {
      const module = matched120.module;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "TagFilter": {
      const tag = matched120.tag;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "TagIndex": {
      const stdout = matched120.stdout;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "TagStatus": {
      const host = matched120.host;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "TagEnable": {
      const host = matched120.host;
      const tag = matched120.tag;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "TagDisable": {
      const host = matched120.host;
      const tag = matched120.tag;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "ModuleEnable": {
      const host = matched120.host;
      const module = matched120.module;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
    case "ModuleDisable": {
      const host = matched120.host;
      const module = matched120.module;
      return { _tag: "TagCommandLoad" as const, token: false };
    }
  }
}

export function moduleEnableRefusal(host: string, module: string): TagCommandOutcome {
  return stderrOutcome(1, ("" + "firn module enable: no module-level force-on in tag-driven hosts.\n" + "\n" + "  " + module + " has no '" + host + " disables " + module + "' fact, so there is\n" + "  nothing to un-blacklist. To activate it on this host:\n" + "\n" + "    - opt in via a tag:    firn tag opt-in <tag>+" + module + "\n" + "      (where the module can opt into <tag>)\n" + "    - or enable a tag the module is tagged with:\n" + "                            firn tag enable <tag>\n" + "    - or turn it on in hosts/" + host + "/configuration.gal:\n" + "                            " + host + " turns on " + module + "\n"));
}

export function runIndex(modules: r.ModuleTags[], stdout: boolean): TagCommandOutcome {
  const matched123 = c.renderTagIndex(modules);
  switch (matched123._tag) {
    case "TagIndexRejected": {
      const message = matched123.message;
      return stderrOutcome(1, ("" + "firn tag index: " + message + "\n"));
    }
    case "TagIndexRendered": {
      const text = matched123.text;
      if (stdout) {
        return stdoutOutcome(text);
      }
      return makeTagCommandOutcome(0, [{ _tag: "CommandWrite" as const, path: ".firn-cache/tags.jsonl", text: text, makeParents: true, label: "firn tag index" }, { _tag: "CommandStdout" as const, text: ("" + "firn tag index: wrote " + modules.length + " entries \u2192 .firn-cache/tags.jsonl\n") }]);
    }
  }
}

export function runShow(modules: r.ModuleTags[], name: string): TagCommandOutcome {
  const matched124 = c.findModule(modules, name);
  switch (matched124._tag) {
    case "ModuleMissing": {
      const missing = matched124.name;
      return stderrOutcome(1, ("" + "firn tag show: no module named '" + missing + "'\n"));
    }
    case "ModuleFound": {
      const module = matched124.value;
      return stdoutOutcome(c.renderTagShow(module));
    }
  }
}

export function runStatus(repository: TagCommandRepository, host: string): TagCommandOutcome {
  const matched125 = findHost(repository, host);
  switch (matched125._tag) {
    case "TagCommandHostMissing": {
      const missing = matched125.host;
      return missingStatusOutcome(missing);
    }
    case "TagCommandHostFound": {
      const document = matched125.document;
      return stdoutOutcome(c.renderTagStatus(repository.modules, document));
    }
  }
}

export function runHostMutation(repository: TagCommandRepository, action: TagCommandAction): TagCommandOutcome {
  const hostValue: string | null = actionHost(action);
  if ((hostValue === null)) {
    return stderrOutcome(1, "firn: internal missing host\n");
  }
  const host: string = hostValue;
  const matched126 = findHost(repository, host);
  switch (matched126._tag) {
    case "TagCommandHostMissing": {
      const missing = matched126.host;
      return missingMutationOutcome(missing);
    }
    case "TagCommandHostFound": {
      const document = matched126.document;
      const matched127 = action;
      switch (matched127._tag) {
        case "TagEnable": {
          const ignored = matched127.host;
          const tag = matched127.tag;
          return mutationOutcome(host, c.enableTag(document, tag));
        }
        case "TagDisable": {
          const ignored = matched127.host;
          const tag = matched127.tag;
          return mutationOutcome(host, c.disableTag(document, tag));
        }
        case "TagOptIn": {
          const ignored = matched127.host;
          const leaf = matched127.leaf;
          const matched128 = c.splitTagModule(leaf);
          switch (matched128._tag) {
            case "TagModuleRejected": {
              const invalid = matched128.leaf;
              return malformedTagModuleOutcome(invalid);
            }
            case "TagModuleParsed": {
              const tag = matched128.tag;
              const module = matched128.module;
              return mutationOutcome(host, c.addTagEdit(document, tag, module, true));
            }
          }
        }
        case "TagOptOut": {
          const ignored = matched127.host;
          const leaf = matched127.leaf;
          const matched129 = c.splitTagModule(leaf);
          switch (matched129._tag) {
            case "TagModuleRejected": {
              const invalid = matched129.leaf;
              return malformedTagModuleOutcome(invalid);
            }
            case "TagModuleParsed": {
              const tag = matched129.tag;
              const module = matched129.module;
              return mutationOutcome(host, c.addTagEdit(document, tag, module, false));
            }
          }
        }
        case "ModuleDisable": {
          const ignored = matched127.host;
          const module = matched127.module;
          return mutationOutcome(host, c.disableModule(document, module));
        }
        case "ModuleEnable": {
          const ignored = matched127.host;
          const module = matched127.module;
          if (r.stringMember(document.tags.disabled, module)) {
            return mutationOutcome(host, c.enableModule(document, module));
          }
          return moduleEnableRefusal(host, module);
        }
        case "TagList": {
          const token = matched127.token;
          return stderrOutcome(1, "firn: internal non-mutation action\n");
        }
        case "TagShow": {
          const module = matched127.module;
          return stderrOutcome(1, "firn: internal non-mutation action\n");
        }
        case "TagFilter": {
          const tag = matched127.tag;
          return stderrOutcome(1, "firn: internal non-mutation action\n");
        }
        case "TagIndex": {
          const stdout = matched127.stdout;
          return stderrOutcome(1, "firn: internal non-mutation action\n");
        }
        case "TagStatus": {
          const statusHost = matched127.host;
          return stderrOutcome(1, "firn: internal non-mutation action\n");
        }
      }
    }
  }
}

export function runTagCommand(repository: TagCommandRepository, action: TagCommandAction): TagCommandOutcome {
  const matched130 = action;
  switch (matched130._tag) {
    case "TagList": {
      const token = matched130.token;
      return stdoutOutcome(c.renderTagList(repository.modules));
    }
    case "TagShow": {
      const module = matched130.module;
      return runShow(repository.modules, module);
    }
    case "TagFilter": {
      const tag = matched130.tag;
      return stdoutOutcome(c.renderTagFilter(repository.modules, tag));
    }
    case "TagIndex": {
      const stdout = matched130.stdout;
      return runIndex(repository.modules, stdout);
    }
    case "TagStatus": {
      const host = matched130.host;
      return runStatus(repository, host);
    }
    case "TagEnable": {
      const host = matched130.host;
      const tag = matched130.tag;
      return runHostMutation(repository, action);
    }
    case "TagDisable": {
      const host = matched130.host;
      const tag = matched130.tag;
      return runHostMutation(repository, action);
    }
    case "TagOptIn": {
      const host = matched130.host;
      const leaf = matched130.leaf;
      return runHostMutation(repository, action);
    }
    case "TagOptOut": {
      const host = matched130.host;
      const leaf = matched130.leaf;
      return runHostMutation(repository, action);
    }
    case "ModuleEnable": {
      const host = matched130.host;
      const module = matched130.module;
      return runHostMutation(repository, action);
    }
    case "ModuleDisable": {
      const host = matched130.host;
      const module = matched130.module;
      return runHostMutation(repository, action);
    }
  }
}

export function outcomeStdout(outcome: TagCommandOutcome): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= outcome.effects.length)) {
      return result;
    }
    const matched132 = outcome.effects[index];
    switch (matched132._tag) {
      case "CommandStdout": {
        const text = matched132.text;
        [index, result] = [(index + 1), ("" + result + text)];
        continue;
      }
      case "CommandStderr": {
        const text = matched132.text;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "CommandWrite": {
        const path = matched132.path;
        const text = matched132.text;
        const makeParents = matched132.makeParents;
        const label = matched132.label;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "CommandEditFacts": {
        const path = matched132.path;
        const remove = matched132.remove;
        const add = matched132.add;
        const label = matched132.label;
        [index, result] = [(index + 1), result];
        continue;
      }
    }
  }
}

export function outcomeStderr(outcome: TagCommandOutcome): string {
  let index: number = 0;
  let result: string = "";
  while (true) {
    if ((index >= outcome.effects.length)) {
      return result;
    }
    const matched134 = outcome.effects[index];
    switch (matched134._tag) {
      case "CommandStdout": {
        const text = matched134.text;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "CommandStderr": {
        const text = matched134.text;
        [index, result] = [(index + 1), ("" + result + text)];
        continue;
      }
      case "CommandWrite": {
        const path = matched134.path;
        const text = matched134.text;
        const makeParents = matched134.makeParents;
        const label = matched134.label;
        [index, result] = [(index + 1), result];
        continue;
      }
      case "CommandEditFacts": {
        const path = matched134.path;
        const remove = matched134.remove;
        const add = matched134.add;
        const label = matched134.label;
        [index, result] = [(index + 1), result];
        continue;
      }
    }
  }
}

export function outcomeEffectKinds(outcome: TagCommandOutcome): string[] {
  let index: number = 0;
  let result: string[] = [];
  while (true) {
    if ((index >= outcome.effects.length)) {
      return result;
    }
    const matched136 = outcome.effects[index];
    switch (matched136._tag) {
      case "CommandStdout": {
        const text = matched136.text;
        [index, result] = [(index + 1), [...result, "stdout"]];
        continue;
      }
      case "CommandStderr": {
        const text = matched136.text;
        [index, result] = [(index + 1), [...result, "stderr"]];
        continue;
      }
      case "CommandWrite": {
        const path = matched136.path;
        const text = matched136.text;
        const makeParents = matched136.makeParents;
        const label = matched136.label;
        [index, result] = [(index + 1), [...result, "write"]];
        continue;
      }
      case "CommandEditFacts": {
        const path = matched136.path;
        const remove = matched136.remove;
        const add = matched136.add;
        const label = matched136.label;
        [index, result] = [(index + 1), [...result, "edit"]];
        continue;
      }
    }
  }
}
