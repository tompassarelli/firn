import * as views from './firn_views.ts';

export type HostResult<T> = ({ tag: 'ok' } & T) | { tag: 'error'; errno: number };
export type ViewsHost = {
  env(name: string): string | null;
  hostname(): HostResult<{ hostname: string }>;
  pathKind(path: string): HostResult<{ kind: number }>;
  readTextBounded(path: string, limit: number): HostResult<{ text: string }>;
  runCapture(argv: string[], input: string, limit: number): HostResult<views.ChildResult>;
  err(text: string): void;
  out(text: string): void;
  wallNanoseconds(): number;
  stdoutTty(): boolean;
};

const maxJsonBytes = 134217728;
const maxChildOutput = 16777216;
type TextLoadResult = { tag: 'TextLoaded'; text: string } | { tag: 'TextMissing'; path: string } | { tag: 'TextLoadRejected'; message: string };
type QueryTextResult = { tag: 'QueryText'; text: string } | { tag: 'QueryTextRejected'; message: string };

export function run(argv: string[], host: ViewsHost): number {
  let root = host.env('FIRN_REPO');
  if (root === null) {
    const home = host.env('HOME');
    root = home === null ? null : home + '/code/nixos-config/main';
  }
  const emitError = (message: string): number => { host.err(message); return 1; };
  const emitResult = (result: views.CommandResult): number => {
    if (result.stdout !== '') host.out(result.stdout);
    if (result.stderr !== '') host.err(result.stderr);
    return result.status;
  };
  if (root === null) return emitError('firn views: FIRN_REPO and HOME are not set\n');

  function readText(relative: string, limit: number, required: boolean): TextLoadResult {
    const absolute = root + '/' + relative;
    const kind = host.pathKind(absolute);
    if (kind.tag === 'error') {
      if (kind.errno === 2) return required ? { tag: 'TextLoadRejected', message: `firn views: missing '${relative}'\n` } : { tag: 'TextMissing', path: relative };
      return { tag: 'TextLoadRejected', message: `firn views: cannot inspect '${relative}': errno ${kind.errno}\n` };
    }
    if (kind.kind !== 1 && kind.kind !== 3) return { tag: 'TextLoadRejected', message: `firn views: not a file '${relative}'\n` };
    const result = host.readTextBounded(absolute, limit);
    return result.tag === 'error'
      ? { tag: 'TextLoadRejected', message: `firn views: cannot read '${relative}': errno ${result.errno}\n` }
      : { tag: 'TextLoaded', text: result.text };
  }

  function childResult(argv: string[], stdin: string): views.ChildResult {
    const result = host.runCapture(argv, stdin, maxChildOutput);
    return result.tag === 'error'
      ? views.childResult(-result.errno, '', `firn views: cannot run '${argv[0]}': errno ${result.errno}\n`)
      : views.childResult(result.status, result.stdout, result.stderr);
  }

  function runPlatform(action: views.ViewsAction): number {
    const metadata = readText('config/platforms.json', maxJsonBytes, true);
    if (metadata.tag !== 'TextLoaded') return emitError(metadata.tag === 'TextLoadRejected' ? metadata.message : 'firn views: missing platforms\n');
    const rows = childResult(['find', root + '/modules', '-mindepth', '2', '-maxdepth', '2', '-name', 'default.nix', '-printf', '%h\n'], '');
    if (rows.status !== 0) return emitResult(rows);
    try {
      const platforms = JSON.parse(metadata.text);
      const names = rows.stdout.trim().split('\n').filter(Boolean).map(path => path.split('/').at(-1)!).sort();
      const everywhere: [string, string][] = names.flatMap(module => Object.entries(platforms).filter(([, data]: any) => data.all).map(([platform]) => [module, platform]));
      const supported: [string, string][] = [];
      for (const module of names) {
        const loaded = readText(`modules/${module}/metadata.json`, maxJsonBytes, false);
        if (loaded.tag === 'TextLoadRejected') return emitError(loaded.message);
        if (loaded.tag === 'TextLoaded') for (const platform of JSON.parse(loaded.text).supports ?? []) supported.push([module, platform]);
      }
      const verdicts = views.platformMatrix(names, [...everywhere, ...supported].map(([module, platform]) => views.platformRow(module, platform)));
      switch (action._tag) {
        case 'PlatformList': return emitResult(views.renderPlatformList(action.selection, verdicts));
        case 'PlatformShow': return emitResult(views.renderPlatformShow(action.module, verdicts));
        case 'PlatformSafelist': return emitResult(views.renderPlatformSafelist(everywhere.map(([module, platform]) => views.platformRow(module, platform)), supported.map(([module, platform]) => views.platformRow(module, platform))));
        default: return emitError('firn views: invalid platform action\n');
      }
    } catch (error) { return emitError(`firn views: invalid platform metadata: ${error}\n`); }
  }

  const parsed = views.parseViewsArgv(argv, '');
  if (parsed._tag === 'InvalidViewsArgv') {
    host.err('Usage: firn flake inputs [all]\n       firn platform list [all|darwin|linux]\n       firn platform show <module>\n       firn platform safelist [all]\n       firn schema explain <path-or-error>\n       firn host gen [host]\n');
    return 64;
  }
  let action = parsed.action;
  if (action._tag === 'HostGeneration' && action.host === '') {
    const configured = host.env('FIRN_HOST');
    let hostname: string;
    if (configured !== null && configured.length > 0) hostname = configured;
    else {
      const result = host.hostname();
      if (result.tag === 'error') return emitError(`firn views: cannot read hostname: errno ${result.errno}\n`);
      if (result.hostname === '') return emitError('firn views: hostname is empty\n');
      hostname = result.hostname;
    }
    action = { _tag: 'HostGeneration', host: hostname };
  }
  switch (action._tag) {
    case 'FlakeInputs': {
      const loaded = readText('flake.lock', maxJsonBytes, true);
      if (loaded.tag === 'TextMissing') return emitError(`firn views: missing '${loaded.path}'\n`);
      if (loaded.tag === 'TextLoadRejected') return emitError(loaded.message);
      const rows = views.flakeRows(loaded.text, Math.trunc(host.wallNanoseconds() / 1000000000));
      if (rows._tag === 'FlakeRowsRejected') return emitError(`firn flake inputs: ${rows.message}\n`);
      host.out(views.renderFlakeRows(rows.rows, host.stdoutTty()));
      return 0;
    }
    case 'PlatformList': case 'PlatformShow': case 'PlatformSafelist': return runPlatform(action);
    case 'SchemaExplain': {
      const option = views.extractOptionPath(action.input);
      if (option === null) return emitError(`firn schema explain: couldn't extract an option path from: ${action.input}\n`);
      const cache = readText('.firn-cache/schema.json', maxJsonBytes, false);
      if (cache.tag === 'TextLoadRejected') return emitError(cache.message);
      if (cache.tag === 'TextLoaded') {
        try {
          const entries = JSON.parse(cache.text), entry = entries.find(row => row.name === option);
          if (entry) {
            host.out(`path:  ${option}\ntype:  ${entry.t}\nDefault: ${JSON.stringify(entry.default ?? '<not cached>')}\n${entry.description ?? ''}\nDeclarations:\n${(entry.declarations ?? []).map(path => '  ' + path + '\n').join('')}`);
            const refs = childResult(['rg', '-n', '--fixed-strings', '--glob', '*.nix', '--glob', '*.json', '--', option, root + '/modules', root + '/hosts', root + '/config'], '');
            if (refs.status === 0) host.out('References:\n' + refs.stdout);
            return 0;
          }
          const prefix = option.slice(0, option.lastIndexOf('.') + 1);
          host.err(`firn schema explain: unknown option ${option}\n` + entries.filter(row => row.name.startsWith(prefix)).sort((a, b) => Number(b.name.startsWith(option)) - Number(a.name.startsWith(option)) || a.name.localeCompare(b.name)).slice(0, 8).map(row => '  ' + row.name + '\n').join(''));
          return 1;
        } catch (error) { return emitError(`firn schema explain: invalid schema cache: ${error}\n`); }
      }
      const hostName = host.env('FIRN_HOST') ?? 'whiterabbit';
      const expression = `options: let path = builtins.fromJSON ${JSON.stringify(JSON.stringify(option.split('.')))}; walk = names: value: if names == [] then value else walk (builtins.tail names) value.\${builtins.head names}; entry = walk path options; in { type = entry.type.description or entry.type.name; description = entry.description or ""; declarations = map builtins.toString (entry.declarations or []); default = if entry ? default then (let attempt = builtins.tryEval (builtins.toJSON entry.default); in if attempt.success then builtins.fromJSON attempt.value else "<unevaluated>") else "<none>"; }`;
      const result = childResult(['nix', 'eval', '--json', `path:${root}#nixosConfigurations.${hostName}.options`, '--apply', expression], '');
      if (result.status !== 0) return emitResult(result);
      try {
        const entry = JSON.parse(result.stdout);
        host.out(`${option}\nType: ${entry.type}\nDefault: ${JSON.stringify(entry.default)}\n${typeof entry.description === 'string' ? entry.description : JSON.stringify(entry.description)}\nDeclarations:\n${entry.declarations.map(path => '  ' + path + '\n').join('')}`);
      } catch (error) { return emitError(`firn schema explain: invalid option metadata: ${error}\n`); }
      const refs = childResult(['rg', '-n', '--fixed-strings', '--glob', '*.nix', '--glob', '*.json', '--', option, root + '/modules', root + '/hosts', root + '/config'], '');
      if (refs.status > 1) return emitResult(refs);
      if (refs.stdout !== '') host.out('References:\n' + refs.stdout);
      return 0;
    }
    case 'HostGeneration': return emitResult(views.renderHostGeneration(childResult(['nixos-rebuild', 'list-generations'], '')));
  }
}
