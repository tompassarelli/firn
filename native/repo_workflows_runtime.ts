import { parseRepoWorkflowArgv, repoWorkflowPlan, splitLines, type ProcessBoundary, type ProcessObservation, type RepoWorkflowAction, type WatchOwnership } from './repo_workflows.ts';

type CaptureResult = { ok: true; status: number; stdout: string; stderr: string } | { ok: false; errno: number };
export type WorkflowBridge = {
  env(name: string): string | null;
  out(text: string): void;
  err(text: string): void;
  runInherit(argv: string[]): number;
  runCapture(argv: string[], stdin: string, maxOutput: number): CaptureResult;
  writeTextAtomic(path: string, text: string): number;
  checkFirstPartyInputSkew(root: string): number;
};

const maxProcessOutput = 67108864;
const watchOwnership: WatchOwnership = { timeoutSeconds: 30, maxEvents: 1 };

function repositoryRoot(bridge: WorkflowBridge): string | null {
  const explicit = bridge.env('FIRN_REPO');
  if (explicit !== null) return explicit;
  const home = bridge.env('HOME');
  return home === null ? null : `${home}/code/nixos-config/main`;
}

function usageError(bridge: WorkflowBridge): number {
  bridge.err('Usage: firn repo validate|lint|diff|doctor|pin-ancestry|watch|architecture|upgrade [leaf]\n');
  return 64;
}

function observationFromCapture(result: CaptureResult, argv: string[]): ProcessObservation {
  return result.ok ? { status: result.status, stdout: result.stdout, stderr: result.stderr }
    : { status: 1, stdout: '', stderr: `firn repo: cannot run ${argv[0]}: errno ${result.errno}\n` };
}

function executeProcess(bridge: WorkflowBridge, process: ProcessBoundary): ProcessObservation {
  switch (process.kind) {
    case 'InheritProcess': return { status: bridge.runInherit(process.argv), stdout: '', stderr: '' };
    case 'CompareProcess': {
      const status = bridge.runInherit(process.argv);
      return { status: status === 0 || status === 1 ? 0 : status, stdout: '', stderr: '' };
    }
    case 'CaptureProcess': return observationFromCapture(bridge.runCapture(process.argv, process.stdin, process.maxOutput), process.argv);
    case 'CaptureToFileProcess': {
      const observed = observationFromCapture(bridge.runCapture(process.argv, process.stdin, process.maxOutput), process.argv);
      if (observed.status !== 0) return observed;
      const errno = bridge.writeTextAtomic(process.outputPath, observed.stdout);
      return errno === 0 ? { status: 0, stdout: '', stderr: observed.stderr }
        : { status: 1, stdout: '', stderr: `firn repo: cannot write ${process.outputPath}: errno ${errno}\n` };
    }
  }
}

function emitObservation(bridge: WorkflowBridge, observation: ProcessObservation): number {
  if (observation.stdout !== '') bridge.out(observation.stdout);
  if (observation.stderr !== '') bridge.err(observation.stderr);
  return observation.status;
}

function executeProcesses(bridge: WorkflowBridge, processes: ProcessBoundary[]): number {
  for (const process of processes) {
    const status = emitObservation(bridge, executeProcess(bridge, process));
    if (status !== 0) return status;
  }
  return 0;
}

type TrackedPathsResult = { kind: 'TrackedPathsLoaded'; paths: string[] } | { kind: 'TrackedPathsRejected'; message: string };

function trackedPaths(bridge: WorkflowBridge, root: string): TrackedPathsResult {
  const result = bridge.runCapture(['git', '-C', root, 'ls-files'], '', maxProcessOutput);
  if (!result.ok) return { kind: 'TrackedPathsRejected', message: `firn repo: cannot run git: errno ${result.errno}\n` };
  return result.status === 0 ? { kind: 'TrackedPathsLoaded', paths: splitLines(result.stdout) }
    : { kind: 'TrackedPathsRejected', message: result.stderr === '' ? `firn repo: git ls-files failed with status ${result.status}\n` : result.stderr };
}

function actionNeedsTracked(action: RepoWorkflowAction): boolean {
  return action.kind === 'RepoLint' || action.kind === 'RepoArchitecture';
}

function pinAncestryStatus(bridge: WorkflowBridge, root: string, action: RepoWorkflowAction): number {
  return action.kind === 'RepoDoctor' || action.kind === 'RepoPinAncestry' ? bridge.checkFirstPartyInputSkew(root) : 0;
}

function executeAction(bridge: WorkflowBridge, root: string, action: RepoWorkflowAction): number {
  const loaded: TrackedPathsResult = actionNeedsTracked(action) ? trackedPaths(bridge, root) : { kind: 'TrackedPathsLoaded', paths: [] };
  if (loaded.kind === 'TrackedPathsRejected') {
    bridge.err(loaded.message);
    return 1;
  }
  const ancestry = pinAncestryStatus(bridge, root, action);
  if (ancestry !== 0) return ancestry;
  const plan = repoWorkflowPlan(root, action, loaded.paths, watchOwnership);
  const status = executeProcesses(bridge, plan.processes);
  if (status !== 0) return status;
  if (plan.successOutput !== '') bridge.out(plan.successOutput);
  return 0;
}

export function run(bridge: WorkflowBridge, args: string[]): number {
  const parsed = parseRepoWorkflowArgv(args);
  if (parsed.kind === 'InvalidRepoWorkflowArgv') return usageError(bridge);
  const root = repositoryRoot(bridge);
  if (root === null) {
    bridge.err('firn repo: FIRN_REPO and HOME are not set\n');
    return 1;
  }
  return executeAction(bridge, root, parsed.action);
}
