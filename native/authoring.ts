import { decode } from './native_json.ts';

export type SchemaEntry = { _tag: 'SchemaEntry'; name: string; type: string };
export type AuthoringAction = { _tag: 'ModuleAdd' | 'TemplateService' | 'TemplateSubmodule' | 'TemplateHome' | 'TemplateHost' | 'SecretShow' | 'SecretEdit'; name: string } | { _tag: 'SecretList'; token: boolean };
export type AuthoringTarget = { _tag: 'AuthoringTarget'; relative: string; contents: string };
export type AuthoringPlan = { _tag: 'AuthoringPlan'; targets: AuthoringTarget[]; success_output: string };
export type SchemaParseResult = { _tag: 'SchemaParsed'; entries: SchemaEntry[] } | { _tag: 'SchemaRejected'; message: string; offset: number };
export function parseAuthoringArgv(argv: string[]) {
  const tags: Record<string, AuthoringAction['_tag']> = { 'module add': 'ModuleAdd', 'template service': 'TemplateService', 'template submodule': 'TemplateSubmodule', 'template home': 'TemplateHome', 'template host': 'TemplateHost', 'secret show': 'SecretShow', 'secret edit': 'SecretEdit' };
  if ((argv.length === 2 || argv.length === 3 && argv[2] === 'all') && argv[0] === 'secret' && argv[1] === 'list') return { _tag: 'ParsedAuthoring' as const, action: { _tag: 'SecretList' as const, token: false } };
  const tag = tags[`${argv[0]} ${argv[1]}`];
  if (argv.length === 3 && tag) return { _tag: 'ParsedAuthoring' as const, action: { _tag: tag, name: argv[2] } as AuthoringAction };
  return { _tag: 'InvalidAuthoringArgv' as const, argv };
}
export const safeAuthoringName = (name: string) => /^[a-z]/.test(name) && !/[^a-z0-9-]/.test(name);
export const safeSecretName = (name: string) => name.length > 0 && name !== '.' && name !== '..' && !/[\\/\x00]/.test(name);
export const endsWith = (text: string, suffix: string) => text.endsWith(suffix);
export const stringMember = (values: string[], candidate: string) => values.includes(candidate);
export const stripYamlSuffix = (name: string) => name.endsWith('.yaml') ? name.slice(0, -5) : name;
export function selectedServiceEntries(entries: SchemaEntry[], service: string): SchemaEntry[] {
  const prefix = `services.${service}.`;
  const excluded = ['submodule', 'attrsOf', 'lazyAttrsOf', 'anything', 'unspecified', 'package'];
  return entries.filter(entry => entry.name.startsWith(prefix) && entry.name.length > prefix.length && !entry.name.slice(prefix.length).includes('.') && entry.name !== prefix + 'enable' && !excluded.includes(entry.type)).map(entry => entry.name).sort().slice(0, 8).map(name => ({ _tag: 'SchemaEntry', name, type: entries.find(entry => entry.name === name)?.type ?? '?' }));
}

function moduleBody(name: string): string {
  return `{ config, lib, pkgs, ... }:
{
  options.myConfig.modules.${name}.enable = lib.mkEnableOption "${name}";
  config = lib.mkIf config.myConfig.modules.${name}.enable {
    environment.systemPackages = [ pkgs.${name} ];
  };
}
`;
}
function submoduleBody(name: string): string {
  return `{ config, lib, pkgs, ... }:
{
  options.myConfig.modules.${name} = {
    enable = lib.mkEnableOption "${name} configuration";
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra config text.";
    };
  };
  config = lib.mkIf config.myConfig.modules.${name}.enable {
    environment.systemPackages = [ pkgs.${name} ];
  };
}
`;
}
function homeBody(name: string): string {
  return `{ config, lib, ... }:
{
  options.myConfig.modules.${name}.enable = lib.mkEnableOption "${name} (home-manager)";
  config = lib.mkIf config.myConfig.modules.${name}.enable {
    home-manager.users.\${config.myConfig.modules.users.username}.programs.${name}.enable = true;
  };
}
`;
}
function hostConfigurationBody(name: string): string {
  return `{ ... }:
{
  config.myConfig.modules = {
    system.stateVersion = "25.11";
    users.username = "you";
    users.enable = true;
    boot.enable = true;
    networking.enable = true;
  };
}
`;
}
function hostTagsBody(name: string): string {
  return JSON.stringify({ platform: 'linux', enables: ['terminal', 'cli-tools', 'development'], adds: {}, drops: {}, disables: [], turnsOn: ['users', 'boot', 'networking'], turnsOff: [] }, null, 2) + '\n';
}
function serviceBody(name: string, entries: SchemaEntry[]): string {
  return `{ config, lib, ... }:
{
  options.myConfig.modules.${name}.enable = lib.mkEnableOption "${name} service";
  config = lib.mkIf config.myConfig.modules.${name}.enable {
    services.${name}.enable = true;
  };
}
`;
}
export function planAuthoring(action: AuthoringAction, schema: SchemaEntry[]) {
  if (action._tag.startsWith('Secret')) return { _tag: 'AuthoringPlanRejected' as const, message: 'firn authoring: not a scaffold command\n' };
  const name = (action as { name: string }).name;
  if (!safeAuthoringName(name)) return { _tag: 'AuthoringPlanRejected' as const, message: 'firn authoring: invalid name\n' };
  if (action._tag === 'TemplateHost') {
    const configuration = `hosts/${name}/configuration.nix`, tags = `hosts/${name}/tags.json`;
    return { _tag: 'AuthoringPlanReady' as const, plan: { _tag: 'AuthoringPlan' as const, targets: [{ _tag: 'AuthoringTarget' as const, relative: configuration, contents: hostConfigurationBody(name) }, { _tag: 'AuthoringTarget' as const, relative: tags, contents: hostTagsBody(name) }], success_output: `Created ${configuration} (git added)\nCreated ${tags} (git added)\nDon't forget to add ${name} to flake.nix's nixosConfigurations.\n` } };
  }
  const relative = `modules/${name}/default.nix`;
  const contents = action._tag === 'ModuleAdd' ? moduleBody(name) : action._tag === 'TemplateSubmodule' ? submoduleBody(name) : action._tag === 'TemplateHome' ? homeBody(name) : serviceBody(name, schema);
  const count = selectedServiceEntries(schema, name).length;
  const summary = action._tag !== 'TemplateService' ? '' : count === 0 ? `  (no schema entries found for services.${name} — schema cache stale or service not in nixpkgs?)\n` : `  schema lists ${count} common options for services.${name}\n`;
  return { _tag: 'AuthoringPlanReady' as const, plan: { _tag: 'AuthoringPlan' as const, targets: [{ _tag: 'AuthoringTarget' as const, relative, contents }, { _tag: 'AuthoringTarget' as const, relative: `modules/${name}/metadata.json`, contents: JSON.stringify({ tags: [], optIn: [], overrides: {}, supports: [], flakeInputs: {} }, null, 2) + '\n' }], success_output: `Created ${relative} (git added)\n${summary}` } };
}

export function schemaEntriesFromJson(source: string): SchemaParseResult {
  const decoded = decode(source);
  if (decoded.tag === 'JsonDecodeError') return { _tag: 'SchemaRejected', message: decoded.message, offset: decoded.offset };
  const events = decoded.events;
  const rejected = (message: string, offset: number): SchemaParseResult => ({ _tag: 'SchemaRejected', message, offset });
  if (events.length < 2 || events[0].tag !== 'JsonArrayStart') return rejected('expected a JSON array', 0);
  const entries: SchemaEntry[] = [];
  let index = 1;
  while (index < events.length) {
    const event = events[index];
    if (event.tag === 'JsonArrayEnd') return index + 1 === events.length ? { _tag: 'SchemaParsed', entries } : rejected('unexpected events after schema array', event.offset);
    if (event.tag !== 'JsonObjectStart') return rejected('schema entries must be objects', event.offset);
    let end = index + 1, depth = 0;
    for (; end < events.length; end++) {
      const tag = events[end].tag;
      if (tag === 'JsonObjectStart' || tag === 'JsonArrayStart') depth++;
      else if (tag === 'JsonObjectEnd') { if (depth === 0) break; depth--; }
      else if (tag === 'JsonArrayEnd') depth--;
    }
    if (end === events.length) return rejected('unterminated schema entry', event.offset);
    let name: string | null = null, type: string | null = null;
    depth = 0;
    for (let scan = index + 1; scan < end; scan++) {
      const current = events[scan];
      if (current.tag === 'JsonObjectStart' || current.tag === 'JsonArrayStart') depth++;
      else if (current.tag === 'JsonObjectEnd' || current.tag === 'JsonArrayEnd') depth--;
      else if (current.tag === 'JsonKey' && depth === 0 && scan + 1 < end) {
        const next = events[scan + 1];
        if (next.tag === 'JsonString') {
          if (current.value === 'name') name = next.value;
          if (current.value === 't') type = next.value;
        }
      }
    }
    if (name === null) return rejected('schema entry requires a string name', event.offset);
    entries.push({ _tag: 'SchemaEntry', name, type: type ?? '?' });
    index = end + 1;
  }
  return rejected('unterminated schema array', 0);
}
