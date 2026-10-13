import * as a from "./activity_core.ts";


export type ActivitySnapshotEntry = Readonly<{ id: string; label: string; current: boolean; workspaceIds: number[]; focusedWorkspaceId: number | null; urgent: boolean; }>;
function makeActivitySnapshotEntry(id: string, label: string, current: boolean, workspaceIds: number[], focusedWorkspaceId: number | null, urgent: boolean): ActivitySnapshotEntry { return { id, label, current, workspaceIds, focusedWorkspaceId, urgent }; }

export type ActivitySnapshot = Readonly<{ current: string; previous: string; entries: ActivitySnapshotEntry[]; floatingIds: number[]; }>;
function makeActivitySnapshot(current: string, previous: string, entries: ActivitySnapshotEntry[], floatingIds: number[]): ActivitySnapshot { return { current, previous, entries, floatingIds }; }

export type BandOutcome = BandsSettled | BandsUnsettled;
export type BandsSettled = Readonly<{ tag: "BandsSettled"; moves: a.WorkspaceMove[]; workspaces: a.Workspace[]; }>;
export function makeBandsSettled(moves: a.WorkspaceMove[], workspaces: a.Workspace[]): BandsSettled { return { tag: "BandsSettled", moves, workspaces }; }
export type BandsUnsettled = Readonly<{ tag: "BandsUnsettled"; moves: a.WorkspaceMove[]; workspaces: a.Workspace[]; limit: number; }>;
export function makeBandsUnsettled(moves: a.WorkspaceMove[], workspaces: a.Workspace[], limit: number): BandsUnsettled { return { tag: "BandsUnsettled", moves, workspaces, limit }; }

export type PlannedStep = FocusStep | MoveColumnStep | NameWorkspaceStep | ReorderStep | SnapshotStep | PersistStep;
export type FocusStep = Readonly<{ tag: "FocusStep"; reference: string; }>;
export function makeFocusStep(reference: string): FocusStep { return { tag: "FocusStep", reference }; }
export type MoveColumnStep = Readonly<{ tag: "MoveColumnStep"; reference: string; }>;
export function makeMoveColumnStep(reference: string): MoveColumnStep { return { tag: "MoveColumnStep", reference }; }
export type NameWorkspaceStep = Readonly<{ tag: "NameWorkspaceStep"; reference: string; name: string; }>;
export function makeNameWorkspaceStep(reference: string, name: string): NameWorkspaceStep { return { tag: "NameWorkspaceStep", reference, name }; }
export type ReorderStep = Readonly<{ tag: "ReorderStep"; reference: string; id: number; targetIndex: number; }>;
export function makeReorderStep(reference: string, id: number, targetIndex: number): ReorderStep { return { tag: "ReorderStep", reference, id, targetIndex }; }
export type SnapshotStep = Readonly<{ tag: "SnapshotStep"; snapshot: ActivitySnapshot; }>;
export function makeSnapshotStep(snapshot: ActivitySnapshot): SnapshotStep { return { tag: "SnapshotStep", snapshot }; }
export type PersistStep = Readonly<{ tag: "PersistStep"; assignments: a.Assignment[]; }>;
export function makePersistStep(assignments: a.Assignment[]): PersistStep { return { tag: "PersistStep", assignments }; }

export type CommandPlan = Readonly<{ state: a.ActivityState; workspaces: a.Workspace[]; steps: PlannedStep[]; settled: boolean; }>;
export function makeCommandPlan(state: a.ActivityState, workspaces: a.Workspace[], steps: PlannedStep[], settled: boolean): CommandPlan { return { state, workspaces, steps, settled }; }

function workspaceWithIndex(workspace: a.Workspace, idx: number): a.Workspace {
  return a.makeWorkspace(workspace.id, idx, workspace.name, workspace.output, workspace.focused, workspace.active, workspace.urgent, workspace.activeWindowId);
}

function workspaceWithName(workspace: a.Workspace, name: string): a.Workspace {
  return a.makeWorkspace(workspace.id, workspace.idx, name, workspace.output, workspace.focused, workspace.active, workspace.urgent, workspace.activeWindowId);
}

function renameWorkspace(workspaces: a.Workspace[], id: number, name: string): a.Workspace[] {
  let index: number = 0;
  let result: a.Workspace[] = [];
  loop1: while (true) {
    if ((index >= workspaces.length)) {
      return result;
    } else {
      const workspace: a.Workspace = workspaces[index];
      [index, result] = [(index + 1), [...result, ((workspace.id === id) ? workspaceWithName(workspace, name) : workspace)]];
      continue loop1;
    }
  }
}

function workspacesOnOutput(workspaces: a.Workspace[], output: string): a.Workspace[] {
  const selected: a.Workspace[] = (() => {
    let index: number = 0;
    let result: a.Workspace[] = [];
    loop2: while (true) {
      if ((index >= workspaces.length)) {
        return result;
      } else {
        const entry: a.Workspace = workspaces[index];
        [index, result] = [(index + 1), ((entry.output === output) ? [...result, entry] : result)];
        continue loop2;
      }
    }
  })();
  return a.sortWorkspacesByIndex(selected);
}

function dropWorkspace(ordered: a.Workspace[], id: number): a.Workspace[] {
  let index: number = 0;
  let result: a.Workspace[] = [];
  loop3: while (true) {
    if ((index >= ordered.length)) {
      return result;
    } else {
      const entry: a.Workspace = ordered[index];
      [index, result] = [(index + 1), ((entry.id === id) ? result : [...result, entry])];
      continue loop3;
    }
  }
}

function insertWorkspaceAt(ordered: a.Workspace[], position: number, workspace: a.Workspace): a.Workspace[] {
  let index: number = 0;
  let result: a.Workspace[] = [];
  loop4: while (true) {
    const placed: a.Workspace[] = ((index === position) ? [...result, workspace] : result);
    if ((index >= ordered.length)) {
      return placed;
    } else {
      [index, result] = [(index + 1), [...placed, ordered[index]]];
      continue loop4;
    }
  }
}

function renumberOutput(ordered: a.Workspace[]): a.Workspace[] {
  let index: number = 0;
  let result: a.Workspace[] = [];
  loop5: while (true) {
    if ((index >= ordered.length)) {
      return result;
    } else {
      [index, result] = [(index + 1), [...result, workspaceWithIndex(ordered[index], (index + 1))]];
      continue loop5;
    }
  }
}

function indexIn(ordered: a.Workspace[], id: number, fallback: number): number {
  let index: number = 0;
  loop6: while (true) {
    if ((index >= ordered.length)) {
      return fallback;
    } else {
      const entry: a.Workspace = ordered[index];
      if ((entry.id === id)) {
        return entry.idx;
      } else {
        [index] = [(index + 1)];
        continue loop6;
      }
    }
  }
}

function mergeOutput(workspaces: a.Workspace[], output: string, renumbered: a.Workspace[]): a.Workspace[] {
  let index: number = 0;
  let result: a.Workspace[] = [];
  loop7: while (true) {
    if ((index >= workspaces.length)) {
      return result;
    } else {
      const entry: a.Workspace = workspaces[index];
      [index, result] = [(index + 1), [...result, ((entry.output === output) ? workspaceWithIndex(entry, indexIn(renumbered, entry.id, entry.idx)) : entry)]];
      continue loop7;
    }
  }
}

function applyMove(workspaces: a.Workspace[], move: a.WorkspaceMove): a.Workspace[] {
  const moved: a.Workspace = move.workspace;
  const output: string = moved.output;
  const ordered: a.Workspace[] = workspacesOnOutput(workspaces, output);
  const remaining: a.Workspace[] = dropWorkspace(ordered, moved.id);
  const position: number = Math.min(Math.max(0, (move.targetIndex - 1)), remaining.length);
  const placed: a.Workspace[] = insertWorkspaceAt(remaining, position, moved);
  return mergeOutput(workspaces, output, renumberOutput(placed));
}

export function bandMoves(outcome: BandOutcome): a.WorkspaceMove[] {
  const matched8 = outcome;
  switch (matched8.tag) {
    case "BandsSettled": {
      const moves = matched8.moves;
      const workspaces = matched8.workspaces;
      return moves;
    }
    case "BandsUnsettled": {
      const moves = matched8.moves;
      const workspaces = matched8.workspaces;
      const limit = matched8.limit;
      return moves;
    }
  }
}

export function bandWorkspaces(outcome: BandOutcome): a.Workspace[] {
  const matched9 = outcome;
  switch (matched9.tag) {
    case "BandsSettled": {
      const moves = matched9.moves;
      const workspaces = matched9.workspaces;
      return workspaces;
    }
    case "BandsUnsettled": {
      const moves = matched9.moves;
      const workspaces = matched9.workspaces;
      const limit = matched9.limit;
      return workspaces;
    }
  }
}

export function bandSettledP(outcome: BandOutcome): boolean {
  const matched10 = outcome;
  switch (matched10.tag) {
    case "BandsSettled": {
      const moves = matched10.moves;
      const workspaces = matched10.workspaces;
      return true;
    }
    case "BandsUnsettled": {
      const moves = matched10.moves;
      const workspaces = matched10.workspaces;
      const limit = matched10.limit;
      return false;
    }
  }
}

function reconcileOutput(state: a.ActivityState, workspaces: a.Workspace[], output: string, limit: number): BandOutcome {
  let steps: number = 0;
  let current: a.Workspace[] = workspaces;
  let moves: a.WorkspaceMove[] = [];
  loop11: while (true) {
    const misplaced: a.WorkspaceMove | null = a.firstMisplaced(a.desiredOrder(state, current, output));
    if ((misplaced == null)) {
      return makeBandsSettled(moves, current);
    } else {
      if ((steps >= limit)) {
        return makeBandsUnsettled(moves, current, limit);
      } else {
        [steps, current, moves] = [(steps + 1), applyMove(current, misplaced), [...moves, misplaced]];
        continue loop11;
      }
    }
  }
}

function outputsOf(workspaces: a.Workspace[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  loop12: while (true) {
    if ((index >= workspaces.length)) {
      return result;
    } else {
      const entry: a.Workspace = workspaces[index];
      const output: string = entry.output;
      [index, result] = [(index + 1), (a.stringMemberP(result, output) ? result : [...result, output])];
      continue loop12;
    }
  }
}

export function defaultBandLimit(workspaces: a.Workspace[]): number {
  return (workspaces.length + 1);
}

export function reconcileBands(state: a.ActivityState, workspaces: a.Workspace[], limit: number): BandOutcome {
  const outputs: string[] = outputsOf(workspaces);
  let index: number = 0;
  let current: a.Workspace[] = workspaces;
  let moves: a.WorkspaceMove[] = [];
  let settled: boolean = true;
  loop13: while (true) {
    if ((index >= outputs.length)) {
      if (settled) {
        return makeBandsSettled(moves, current);
      } else {
        return makeBandsUnsettled(moves, current, limit);
      }
    } else {
      const outcome: BandOutcome = reconcileOutput(state, current, outputs[index], limit);
      [index, current, moves, settled] = [(index + 1), bandWorkspaces(outcome), [...moves, ...bandMoves(outcome)], (settled && bandSettledP(outcome))];
      continue loop13;
    }
  }
}

function reorderSteps(moves: a.WorkspaceMove[]): PlannedStep[] {
  let index: number = 0;
  let result: PlannedStep[] = [];
  loop14: while (true) {
    if ((index >= moves.length)) {
      return result;
    } else {
      const move: a.WorkspaceMove = moves[index];
      const moved: a.Workspace = move.workspace;
      [index, result] = [(index + 1), [...result, makeReorderStep(a.workspaceReference(moved), moved.id, move.targetIndex)]];
      continue loop14;
    }
  }
}

function workspaceIds(workspaces: a.Workspace[]): number[] {
  let index: number = 0;
  let result: number[] = [];
  loop15: while (true) {
    if ((index >= workspaces.length)) {
      return result;
    } else {
      [index, result] = [(index + 1), [...result, workspaces[index].id]];
      continue loop15;
    }
  }
}

function currentWorkspaceReference(workspaces: a.Workspace[], workspace: a.Workspace): string {
  let index: number = 0;
  loop16: while (true) {
    if ((index >= workspaces.length)) {
      return a.workspaceReference(workspace);
    } else {
      const current: a.Workspace = workspaces[index];
      if ((current.id === workspace.id)) {
        return a.workspaceReference(current);
      } else {
        [index] = [(index + 1)];
        continue loop16;
      }
    }
  }
}

function focusedId(workspaces: a.Workspace[]): number | null {
  const lookup: a.WorkspaceLookup = a.focusedWorkspace(workspaces);
  const matched17 = lookup;
  switch (matched17.tag) {
    case "WorkspaceFound": {
      const workspace = matched17.workspace;
      return workspace.id;
    }
    case "WorkspaceMissing": {
      const token = matched17.token;
      return null;
    }
  }
}

function anyUrgentP(workspaces: a.Workspace[]): boolean {
  let index: number = 0;
  loop18: while (true) {
    if ((index >= workspaces.length)) {
      return false;
    } else {
      const entry: a.Workspace = workspaces[index];
      if (entry.urgent) {
        return true;
      } else {
        [index] = [(index + 1)];
        continue loop18;
      }
    }
  }
}

function activityLabel(definition: a.ActivityDef): string {
  const label: string | null = definition.label;
  if ((label == null)) {
    return definition.id;
  } else {
    return label;
  }
}

function snapshotEntry(state: a.ActivityState, workspaces: a.Workspace[], definition: a.ActivityDef): ActivitySnapshotEntry {
  const activity: string = definition.id;
  const members: a.Workspace[] = a.membersOf(state, workspaces, activity);
  return makeActivitySnapshotEntry(activity, activityLabel(definition), (state.current === activity), workspaceIds(members), focusedId(members), anyUrgentP(members));
}

function snapshotOf(state: a.ActivityState, workspaces: a.Workspace[]): ActivitySnapshot {
  const definitions: a.ActivityDef[] = state.defs;
  let index: number = 0;
  let entries: ActivitySnapshotEntry[] = [];
  loop19: while (true) {
    if ((index >= definitions.length)) {
      return makeActivitySnapshot(state.current, state.previous, entries, workspaceIds(a.floatsOf(state, workspaces)));
    } else {
      [index, entries] = [(index + 1), [...entries, snapshotEntry(state, workspaces, definitions[index])]];
      continue loop19;
    }
  }
}

function assignmentNames(assignments: a.Assignment[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  loop20: while (true) {
    if ((index >= assignments.length)) {
      return result;
    } else {
      const entry: a.Assignment = assignments[index];
      const name: string = entry.workspaceName;
      [index, result] = [(index + 1), (a.stringMemberP(result, name) ? result : [...result, name])];
      continue loop20;
    }
  }
}

function assignmentForName(assignments: a.Assignment[], name: string): a.Assignment | null {
  let index: number = 0;
  loop21: while (true) {
    if ((index >= assignments.length)) {
      return null;
    } else {
      const entry: a.Assignment = assignments[index];
      if ((entry.workspaceName === name)) {
        return entry;
      } else {
        [index] = [(index + 1)];
        continue loop21;
      }
    }
  }
}

function persistPayload(assignments: a.Assignment[]): a.Assignment[] {
  const names: string[] = [...assignmentNames(assignments)].sort();
  let index: number = 0;
  let result: a.Assignment[] = [];
  loop22: while (true) {
    if ((index >= names.length)) {
      return result;
    } else {
      const found: a.Assignment | null = assignmentForName(assignments, names[index]);
      [index, result] = [(index + 1), ((found == null) ? result : [...result, found])];
      continue loop22;
    }
  }
}

function planEffects(state: a.ActivityState, workspaces: a.Workspace[], effects: a.ActivityEffect[], limit: number): CommandPlan {
  let index: number = 0;
  let current: a.Workspace[] = workspaces;
  let steps: PlannedStep[] = [];
  let settled: boolean = true;
  loop23: while (true) {
    if ((index >= effects.length)) {
      return makeCommandPlan(state, current, steps, settled);
    } else {
      const effect: a.ActivityEffect = effects[index];
      const matched24 = effect;
      switch (matched24.tag) {
        case "FocusWorkspace": {
          const workspace = matched24.workspace;
          [index, current, steps, settled] = [(index + 1), current, [...steps, makeFocusStep(currentWorkspaceReference(current, workspace))], settled];
          continue loop23;
        }
        case "MoveColumnToWorkspace": {
          const workspace = matched24.workspace;
          [index, current, steps, settled] = [(index + 1), current, [...steps, makeMoveColumnStep(currentWorkspaceReference(current, workspace))], settled];
          continue loop23;
        }
        case "NameWorkspace": {
          const workspace = matched24.workspace;
          const name = matched24.name;
          [index, current, steps, settled] = [(index + 1), renameWorkspace(current, workspace.id, name), [...steps, makeNameWorkspaceStep(currentWorkspaceReference(current, workspace), name)], settled];
          continue loop23;
        }
        case "ReconcileBands": {
          const token = matched24.token;
          const outcome: BandOutcome = reconcileBands(state, current, limit);
          [index, current, steps, settled] = [(index + 1), bandWorkspaces(outcome), [...steps, ...reorderSteps(bandMoves(outcome))], (settled && bandSettledP(outcome))];
          continue loop23;
        }
        case "PublishSnapshot": {
          const token = matched24.token;
          [index, current, steps, settled] = [(index + 1), current, [...steps, makeSnapshotStep(snapshotOf(state, current))], settled];
          continue loop23;
        }
        case "PersistAssignments": {
          const assignments = matched24.assignments;
          [index, current, steps, settled] = [(index + 1), current, [...steps, makePersistStep(persistPayload(assignments))], settled];
          continue loop23;
        }
      }
    }
  }
}

function planCommandBounded(state: a.ActivityState, workspaces: a.Workspace[], command: a.ActivityCommand, limit: number): CommandPlan {
  const outcome: a.CommandOutcome = a.applyCommand(state, workspaces, command);
  return planEffects(outcome.state, workspaces, outcome.effects, limit);
}

export function planCommand(state: a.ActivityState, workspaces: a.Workspace[], command: a.ActivityCommand): CommandPlan {
  return planCommandBounded(state, workspaces, command, defaultBandLimit(workspaces));
}

function planStepKinds(steps: PlannedStep[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  loop25: while (true) {
    if ((index >= steps.length)) {
      return result;
    } else {
      const step: PlannedStep = steps[index];
      [index, result] = [(index + 1), [...result, (() => {
        const matched26 = step;
        switch (matched26.tag) {
          case "FocusStep": {
            const reference = matched26.reference;
            return (String("focus:") + String(reference));
          }
          case "MoveColumnStep": {
            const reference = matched26.reference;
            return (String("move:") + String(reference));
          }
          case "NameWorkspaceStep": {
            const reference = matched26.reference;
            const name = matched26.name;
            return (String("name:") + String(reference) + String("->") + String(name));
          }
          case "ReorderStep": {
            const reference = matched26.reference;
            const id = matched26.id;
            const targetIndex = matched26.targetIndex;
            return (String("reorder:") + String(reference) + String("->") + String(targetIndex));
          }
          case "SnapshotStep": {
            const snapshot = matched26.snapshot;
            return "snapshot";
          }
          case "PersistStep": {
            const assignments = matched26.assignments;
            return "assignments";
          }
        }
      })()]];
      continue loop25;
    }
  }
}
