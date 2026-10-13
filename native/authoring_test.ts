import { parseAuthoringArgv, safeAuthoringName, safeSecretName, planAuthoring, type AuthoringAction } from './authoring.ts';

function actionKind(seed: number, action: AuthoringAction): string {
  return { ModuleAdd: 'module-add', TemplateService: 'template-service', TemplateSubmodule: 'template-submodule', TemplateHome: 'template-home', TemplateHost: 'template-host', SecretList: 'secret-list', SecretShow: 'secret-show', SecretEdit: 'secret-edit' }[action._tag];
}
function actionName(seed: number, action: AuthoringAction): string { return action._tag === 'SecretList' ? '' : action.name; }
function caseArgvGrammar(seed: number): boolean {
  const suffix = seed === 0 ? '' : String(seed);
  const named = (argv: string[], kind: string, name: string) => {
    const result = parseAuthoringArgv(argv);
    return result._tag === 'ParsedAuthoring' && actionKind(seed, result.action) === kind && actionName(seed, result.action) === name;
  };
  const listed = (argv: string[]) => {
    const result = parseAuthoringArgv(argv);
    return result._tag === 'ParsedAuthoring' && actionKind(seed, result.action) === 'secret-list';
  };
  return named(['module', 'add', 'sample-tool' + suffix], 'module-add', 'sample-tool' + suffix)
    && named(['template', 'service', 'openssh' + suffix], 'template-service', 'openssh' + suffix)
    && named(['template', 'submodule', 'sample' + suffix], 'template-submodule', 'sample' + suffix)
    && named(['template', 'home', 'sample' + suffix], 'template-home', 'sample' + suffix)
    && named(['template', 'host', 'sample-host' + suffix], 'template-host', 'sample-host' + suffix)
    && listed(['secret', 'list'])
    && listed(['secret', 'list', 'all'])
    && named(['secret', 'show', 'alpha' + suffix], 'secret-show', 'alpha' + suffix)
    && named(['secret', 'edit', 'alpha' + suffix], 'secret-edit', 'alpha' + suffix)
    && parseAuthoringArgv(['secret', 'list', 'stale'])._tag === 'InvalidAuthoringArgv'
    && parseAuthoringArgv(['host', 'gen', 'whiterabbit'])._tag === 'InvalidAuthoringArgv';
}
function caseNameRefusal(seed: number): boolean {
  const suffix = seed === 0 ? '' : String(seed);
  return safeAuthoringName('sample-tool' + suffix)
    && safeAuthoringName('g203-led' + suffix)
    && !safeAuthoringName('')
    && !safeAuthoringName('.')
    && !safeAuthoringName('..')
    && !safeAuthoringName('../escape')
    && !safeAuthoringName('nested/name')
    && !safeAuthoringName('nested\\name')
    && !safeAuthoringName('Upper' + suffix)
    && !safeAuthoringName('white space')
    && safeSecretName('alpha' + suffix)
    && safeSecretName('alpha' + suffix + ' beta')
    && !safeSecretName('')
    && !safeSecretName('.')
    && !safeSecretName('..')
    && !safeSecretName('/')
    && !safeSecretName('a/b')
    && !safeSecretName('\\')
    && !safeSecretName('a\\b')
    && !safeSecretName(new TextDecoder().decode(new Uint8Array([0])))
    && planAuthoring({ _tag: 'ModuleAdd', name: '../escape' }, [])._tag === 'AuthoringPlanRejected';
}
export function runScenarios(): number {
  if (caseArgvGrammar(0) && caseNameRefusal(0)) return 0;
  console.log('FAIL authoring scenarios');
  return 1;
}
