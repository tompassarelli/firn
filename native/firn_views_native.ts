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

  function galileoBinary(): string {
    const runtime = host.env('FIRN_RUNTIME_BIN');
    if (runtime === null || runtime === '') return 'galileo';
    const candidate = runtime + '/galileo';
    return host.pathKind(candidate).tag === 'ok' ? candidate : 'galileo';
  }

  function galileoQuery(galileo: string, question: string): QueryTextResult {
    const result = host.runCapture(['env', '-C', root!, galileo, 'query', question, '--json'], '', maxChildOutput);
    if (result.tag === 'error') return { tag: 'QueryTextRejected', message: `firn views: cannot run '${galileo}': errno ${result.errno}\n` };
    return result.status === 0 ? { tag: 'QueryText', text: result.stdout }
      : { tag: 'QueryTextRejected', message: result.stderr + `firn views: galileo query '${question}' exited ${result.status}\n` };
  }

  function queryNames(galileo: string, question: string): views.QueryNamesResult {
    const result = galileoQuery(galileo, question);
    if (result.tag === 'QueryTextRejected') return { _tag: 'QueryNamesRejected', message: result.message };
    const decoded = views.queryNamesFromJson(result.text);
    return decoded._tag === 'QueryNamesRejected'
      ? { _tag: 'QueryNamesRejected', message: `firn views: galileo query '${question}': ${decoded.message}\n` } : decoded;
  }

  function queryRows(galileo: string, question: string): views.QueryRowsResult {
    const result = galileoQuery(galileo, question);
    if (result.tag === 'QueryTextRejected') return { _tag: 'QueryRowsRejected', message: result.message };
    const decoded = views.queryRowsFromJson(result.text);
    return decoded._tag === 'QueryRowsRejected'
      ? { _tag: 'QueryRowsRejected', message: `firn views: galileo query '${question}': ${decoded.message}\n` } : decoded;
  }

  function runPlatform(action: views.ViewsAction): number {
    const galileo = galileoBinary();
    const modules = queryNames(galileo, 'all ?m where ?m is a Module');
    if (modules._tag === 'QueryNamesRejected') return emitError(modules.message);
    const everywhere = queryRows(galileo, 'all ?m, ?p where ?m is a Module and ?p allows every module');
    if (everywhere._tag === 'QueryRowsRejected') return emitError(everywhere.message);
    const supported = queryRows(galileo, 'all ?m, ?p where ?m supports ?p');
    if (supported._tag === 'QueryRowsRejected') return emitError(supported.message);
    const verdicts = views.platformMatrix(modules.names, [...everywhere.rows, ...supported.rows]);
    switch (action._tag) {
      case 'PlatformList': return emitResult(views.renderPlatformList(action.selection, verdicts));
      case 'PlatformShow': return emitResult(views.renderPlatformShow(action.module, verdicts));
      case 'PlatformSafelist': return emitResult(views.renderPlatformSafelist(everywhere.rows, supported.rows));
      default: return emitError('firn views: invalid platform action\n');
    }
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
      return emitResult(childResult(['env', '-C', root, galileoBinary(), 'schema', 'explain', option], ''));
    }
    case 'HostGeneration': return emitResult(views.renderHostGeneration(childResult(['nixos-rebuild', 'list-generations'], '')));
  }
}
