

export type ActivityDef = Readonly<{ id: string; label: string | null; bindNames: string[]; bindPrefixes: string[]; }>;
export function makeActivityDef(id: string, label: string | null, bindNames: string[], bindPrefixes: string[]): ActivityDef { return { id, label, bindNames, bindPrefixes }; }

export type Assignment = Readonly<{ workspaceName: string; activity: string; }>;
export function makeAssignment(workspaceName: string, activity: string): Assignment { return { workspaceName, activity }; }

export type Membership = Readonly<{ workspaceId: number; activity: string; }>;
export function makeMembership(workspaceId: number, activity: string): Membership { return { workspaceId, activity }; }

export type LastActive = Readonly<{ activity: string; workspaceId: number; }>;
export function makeLastActive(activity: string, workspaceId: number): LastActive { return { activity, workspaceId }; }

export type Workspace = Readonly<{ id: number; idx: number; name: string | null; output: string; focused: boolean; active: boolean; urgent: boolean; activeWindowId: number | null; }>;
export function makeWorkspace(id: number, idx: number, name: string | null, output: string, focused: boolean, active: boolean, urgent: boolean, activeWindowId: number | null): Workspace { return { id, idx, name, output, focused, active, urgent, activeWindowId }; }

export type ActivityState = Readonly<{ defs: ActivityDef[]; defaultActivity: string; assignments: Assignment[]; members: Membership[]; lastActive: LastActive[]; current: string; previous: string; workspaces: Workspace[]; }>;
export function makeActivityState(defs: ActivityDef[], defaultActivity: string, assignments: Assignment[], members: Membership[], lastActive: LastActive[], current: string, previous: string, workspaces: Workspace[]): ActivityState { return { defs, defaultActivity, assignments, members, lastActive, current, previous, workspaces }; }

export type WorkspaceMove = Readonly<{ workspace: Workspace; targetIndex: number; }>;
export function makeWorkspaceMove(workspace: Workspace, targetIndex: number): WorkspaceMove { return { workspace, targetIndex }; }

export type WorkspaceLookup = WorkspaceFound | WorkspaceMissing;
export type WorkspaceFound = Readonly<{ tag: "WorkspaceFound"; workspace: Workspace; }>;
export function makeWorkspaceFound(workspace: Workspace): WorkspaceFound { return { tag: "WorkspaceFound", workspace }; }
export type WorkspaceMissing = Readonly<{ tag: "WorkspaceMissing"; token: boolean; }>;
export function makeWorkspaceMissing(token: boolean): WorkspaceMissing { return { tag: "WorkspaceMissing", token }; }

export type ActivityCommand = Goto | MoveToActivity | Back | Here | MoveHere | Assign;
export type Goto = Readonly<{ tag: "Goto"; activity: string; }>;
export function makeGoto(activity: string): Goto { return { tag: "Goto", activity }; }
export type MoveToActivity = Readonly<{ tag: "MoveToActivity"; activity: string; }>;
export function makeMoveToActivity(activity: string): MoveToActivity { return { tag: "MoveToActivity", activity }; }
export type Back = Readonly<{ tag: "Back"; token: boolean; }>;
export function makeBack(token: boolean): Back { return { tag: "Back", token }; }
export type Here = Readonly<{ tag: "Here"; ordinal: number; }>;
export function makeHere(ordinal: number): Here { return { tag: "Here", ordinal }; }
export type MoveHere = Readonly<{ tag: "MoveHere"; ordinal: number; }>;
export function makeMoveHere(ordinal: number): MoveHere { return { tag: "MoveHere", ordinal }; }
export type Assign = Readonly<{ tag: "Assign"; activity: string; }>;
export function makeAssign(activity: string): Assign { return { tag: "Assign", activity }; }

export type ActivityEffect = FocusWorkspace | MoveColumnToWorkspace | NameWorkspace | ReconcileBands | PublishSnapshot | PersistAssignments;
export type FocusWorkspace = Readonly<{ tag: "FocusWorkspace"; workspace: Workspace; }>;
export function makeFocusWorkspace(workspace: Workspace): FocusWorkspace { return { tag: "FocusWorkspace", workspace }; }
export type MoveColumnToWorkspace = Readonly<{ tag: "MoveColumnToWorkspace"; workspace: Workspace; }>;
export function makeMoveColumnToWorkspace(workspace: Workspace): MoveColumnToWorkspace { return { tag: "MoveColumnToWorkspace", workspace }; }
export type NameWorkspace = Readonly<{ tag: "NameWorkspace"; workspace: Workspace; name: string; }>;
export function makeNameWorkspace(workspace: Workspace, name: string): NameWorkspace { return { tag: "NameWorkspace", workspace, name }; }
export type ReconcileBands = Readonly<{ tag: "ReconcileBands"; token: boolean; }>;
export function makeReconcileBands(token: boolean): ReconcileBands { return { tag: "ReconcileBands", token }; }
export type PublishSnapshot = Readonly<{ tag: "PublishSnapshot"; token: boolean; }>;
export function makePublishSnapshot(token: boolean): PublishSnapshot { return { tag: "PublishSnapshot", token }; }
export type PersistAssignments = Readonly<{ tag: "PersistAssignments"; assignments: Assignment[]; }>;
export function makePersistAssignments(assignments: Assignment[]): PersistAssignments { return { tag: "PersistAssignments", assignments }; }

export type CommandOutcome = Readonly<{ state: ActivityState; effects: ActivityEffect[]; }>;
export function makeCommandOutcome(state: ActivityState, effects: ActivityEffect[]): CommandOutcome { return { state, effects }; }

function startsWithP(text: string, prefix: string): boolean {
  return ((prefix.length <= text.length) && (text.substring(0, prefix.length) === prefix));
}

export function stringMemberP(values: string[], candidate: string): boolean {
  let index: number = 0;
  loop1: while (true) {
    if ((index >= values.length)) {
      return false;
    } else {
      if ((values[index] === candidate)) {
        return true;
      } else {
        [index] = [(index + 1)];
        continue loop1;
      }
    }
  }
}

function workspaceIdMemberP(workspaces: Workspace[], candidate: number): boolean {
  let index: number = 0;
  loop2: while (true) {
    if ((index >= workspaces.length)) {
      return false;
    } else {
      if ((workspaces[index].id === candidate)) {
        return true;
      } else {
        [index] = [(index + 1)];
        continue loop2;
      }
    }
  }
}

function activityRank(state: ActivityState, activity: string): number {
  let index: number = 0;
  loop3: while (true) {
    if ((index >= state.defs.length)) {
      return 9999;
    } else {
      if ((state.defs[index].id === activity)) {
        return index;
      } else {
        [index] = [(index + 1)];
        continue loop3;
      }
    }
  }
}

function anyPrefixMatchesP(prefixes: string[], workspaceName: string): boolean {
  let index: number = 0;
  loop4: while (true) {
    if ((index >= prefixes.length)) {
      return false;
    } else {
      if (startsWithP(workspaceName, prefixes[index])) {
        return true;
      } else {
        [index] = [(index + 1)];
        continue loop4;
      }
    }
  }
}

function matchBinding(defs: ActivityDef[], workspaceName: string | null): string | null {
  if ((workspaceName == null)) {
    return null;
  } else {
    let index: number = 0;
    loop5: while (true) {
      if ((index >= defs.length)) {
        return null;
      } else {
        const definition: ActivityDef = defs[index];
        if (((definition.id === workspaceName) || stringMemberP(definition.bindNames, workspaceName) || anyPrefixMatchesP(definition.bindPrefixes, workspaceName))) {
          return definition.id;
        } else {
          [index] = [(index + 1)];
          continue loop5;
        }
      }
    }
  }
}

function assignmentFor(assignments: Assignment[], workspaceName: string | null): string | null {
  if ((workspaceName == null)) {
    return null;
  } else {
    let index: number = 0;
    loop6: while (true) {
      if ((index >= assignments.length)) {
        return null;
      } else {
        const assignment: Assignment = assignments[index];
        if ((assignment.workspaceName === workspaceName)) {
          return assignment.activity;
        } else {
          [index] = [(index + 1)];
          continue loop6;
        }
      }
    }
  }
}

function membershipFor(members: Membership[], workspaceId: number): string | null {
  let index: number = 0;
  loop7: while (true) {
    if ((index >= members.length)) {
      return null;
    } else {
      const membership: Membership = members[index];
      if ((membership.workspaceId === workspaceId)) {
        return membership.activity;
      } else {
        [index] = [(index + 1)];
        continue loop7;
      }
    }
  }
}

function putMembership(members: Membership[], workspaceId: number, activity: string): Membership[] {
  let index: number = 0;
  let found: boolean = false;
  let result: Membership[] = [];
  loop8: while (true) {
    if ((index >= members.length)) {
      if (found) {
        return result;
      } else {
        return [...result, makeMembership(workspaceId, activity)];
      }
    } else {
      const membership: Membership = members[index];
      if ((membership.workspaceId === workspaceId)) {
        [index, found, result] = [(index + 1), true, [...result, makeMembership(workspaceId, activity)]];
        continue loop8;
      } else {
        [index, found, result] = [(index + 1), found, [...result, membership]];
        continue loop8;
      }
    }
  }
}

function pruneMembers(members: Membership[], workspaces: Workspace[]): Membership[] {
  let index: number = 0;
  let result: Membership[] = [];
  loop9: while (true) {
    if ((index >= members.length)) {
      return result;
    } else {
      const membership: Membership = members[index];
      [index, result] = [(index + 1), (workspaceIdMemberP(workspaces, membership.workspaceId) ? [...result, membership] : result)];
      continue loop9;
    }
  }
}

function maxWorkspaceIndexOnOutput(workspaces: Workspace[], output: string): number {
  let index: number = 0;
  let maximum: number = 0;
  loop10: while (true) {
    if ((index >= workspaces.length)) {
      return maximum;
    } else {
      const workspace: Workspace = workspaces[index];
      [index, maximum] = [(index + 1), ((workspace.output === output) ? Math.max(maximum, workspace.idx) : maximum)];
      continue loop10;
    }
  }
}

function floatingP(workspaces: Workspace[], workspace: Workspace): boolean {
  return ((workspace.name == null) && (workspace.activeWindowId == null) && (workspace.idx === maxWorkspaceIndexOnOutput(workspaces, workspace.output)));
}

function adoptionActivity(state: ActivityState, workspace: Workspace): string {
  const assigned: string | null = assignmentFor(state.assignments, workspace.name);
  if ((assigned == null)) {
    const bound: string | null = matchBinding(state.defs, workspace.name);
    if ((bound == null)) {
      return state.current;
    } else {
      return bound;
    }
  } else {
    return assigned;
  }
}

function adoptAll(state: ActivityState, workspaces: Workspace[]): Membership[] {
  let index: number = 0;
  let members: Membership[] = pruneMembers(state.members, workspaces);
  loop11: while (true) {
    if ((index >= workspaces.length)) {
      return members;
    } else {
      const workspace: Workspace = workspaces[index];
      const known: string | null = membershipFor(members, workspace.id);
      [index, members] = [(index + 1), (((known != null) || floatingP(workspaces, workspace)) ? members : putMembership(members, workspace.id, adoptionActivity(state, workspace)))];
      continue loop11;
    }
  }
}

function insertWorkspaceByIndex(ordered: Workspace[], workspace: Workspace): Workspace[] {
  let index: number = 0;
  let inserted: boolean = false;
  let result: Workspace[] = [];
  loop12: while (true) {
    if ((index >= ordered.length)) {
      if (inserted) {
        return result;
      } else {
        return [...result, workspace];
      }
    } else {
      const current: Workspace = ordered[index];
      if ((!(inserted) && (workspace.idx < current.idx))) {
        [index, inserted, result] = [(index + 1), true, [...[...result, workspace], current]];
        continue loop12;
      } else {
        [index, inserted, result] = [(index + 1), inserted, [...result, current]];
        continue loop12;
      }
    }
  }
}

export function sortWorkspacesByIndex(workspaces: Workspace[]): Workspace[] {
  let index: number = 0;
  let ordered: Workspace[] = [];
  loop13: while (true) {
    if ((index >= workspaces.length)) {
      return ordered;
    } else {
      [index, ordered] = [(index + 1), insertWorkspaceByIndex(ordered, workspaces[index])];
      continue loop13;
    }
  }
}

export function focusedWorkspace(workspaces: Workspace[]): WorkspaceLookup {
  let index: number = 0;
  loop14: while (true) {
    if ((index >= workspaces.length)) {
      return makeWorkspaceMissing(false);
    } else {
      const workspace: Workspace = workspaces[index];
      if (workspace.focused) {
        return makeWorkspaceFound(workspace);
      } else {
        [index] = [(index + 1)];
        continue loop14;
      }
    }
  }
}

export function membersOf(state: ActivityState, workspaces: Workspace[], activity: string): Workspace[] {
  let index: number = 0;
  let members: Workspace[] = [];
  loop15: while (true) {
    if ((index >= workspaces.length)) {
      return sortWorkspacesByIndex(members);
    } else {
      const workspace: Workspace = workspaces[index];
      const workspaceActivity: string | null = membershipFor(state.members, workspace.id);
      [index, members] = [(index + 1), ((workspaceActivity === activity) ? [...members, workspace] : members)];
      continue loop15;
    }
  }
}

export function floatsOf(state: ActivityState, workspaces: Workspace[]): Workspace[] {
  let index: number = 0;
  let floats: Workspace[] = [];
  loop16: while (true) {
    if ((index >= workspaces.length)) {
      return sortWorkspacesByIndex(floats);
    } else {
      const workspace: Workspace = workspaces[index];
      [index, floats] = [(index + 1), ((membershipFor(state.members, workspace.id) == null) ? [...floats, workspace] : floats)];
      continue loop16;
    }
  }
}

function workspaceBeforeP(state: ActivityState, left: Workspace, right: Workspace): boolean {
  const leftActivity: string | null = membershipFor(state.members, left.id);
  const rightActivity: string | null = membershipFor(state.members, right.id);
  const leftRank: number = ((leftActivity == null) ? 9999 : activityRank(state, leftActivity));
  const rightRank: number = ((rightActivity == null) ? 9999 : activityRank(state, rightActivity));
  return ((leftRank < rightRank) || ((leftRank === rightRank) && (left.idx < right.idx)));
}

function insertWorkspaceByBand(state: ActivityState, ordered: Workspace[], workspace: Workspace): Workspace[] {
  let index: number = 0;
  let inserted: boolean = false;
  let result: Workspace[] = [];
  loop17: while (true) {
    if ((index >= ordered.length)) {
      if (inserted) {
        return result;
      } else {
        return [...result, workspace];
      }
    } else {
      const current: Workspace = ordered[index];
      if ((!(inserted) && workspaceBeforeP(state, workspace, current))) {
        [index, inserted, result] = [(index + 1), true, [...[...result, workspace], current]];
        continue loop17;
      } else {
        [index, inserted, result] = [(index + 1), inserted, [...result, current]];
        continue loop17;
      }
    }
  }
}

export function desiredOrder(state: ActivityState, workspaces: Workspace[], output: string): Workspace[] {
  let index: number = 0;
  let ordered: Workspace[] = [];
  loop18: while (true) {
    if ((index >= workspaces.length)) {
      return ordered;
    } else {
      const workspace: Workspace = workspaces[index];
      [index, ordered] = [(index + 1), ((workspace.output === output) ? insertWorkspaceByBand(state, ordered, workspace) : ordered)];
      continue loop18;
    }
  }
}

export function firstMisplaced(desired: Workspace[]): WorkspaceMove | null {
  let index: number = 0;
  let target: number = 1;
  loop19: while (true) {
    if ((index >= desired.length)) {
      return null;
    } else {
      const workspace: Workspace = desired[index];
      if ((workspace.idx !== target)) {
        return makeWorkspaceMove(workspace, target);
      } else {
        [index, target] = [(index + 1), (target + 1)];
        continue loop19;
      }
    }
  }
}

export function lastActiveFor(lastActive: LastActive[], activity: string): number | null {
  let index: number = 0;
  loop20: while (true) {
    if ((index >= lastActive.length)) {
      return null;
    } else {
      const entry: LastActive = lastActive[index];
      if ((entry.activity === activity)) {
        return entry.workspaceId;
      } else {
        [index] = [(index + 1)];
        continue loop20;
      }
    }
  }
}

function putLastActive(lastActive: LastActive[], activity: string, workspaceId: number): LastActive[] {
  let index: number = 0;
  let found: boolean = false;
  let result: LastActive[] = [];
  loop21: while (true) {
    if ((index >= lastActive.length)) {
      if (found) {
        return result;
      } else {
        return [...result, makeLastActive(activity, workspaceId)];
      }
    } else {
      const entry: LastActive = lastActive[index];
      if ((entry.activity === activity)) {
        [index, found, result] = [(index + 1), true, [...result, makeLastActive(activity, workspaceId)]];
        continue loop21;
      } else {
        [index, found, result] = [(index + 1), found, [...result, entry]];
        continue loop21;
      }
    }
  }
}

function stateWithWorkspaces(state: ActivityState, members: Membership[], workspaces: Workspace[]): ActivityState {
  return makeActivityState(state.defs, state.defaultActivity, state.assignments, members, state.lastActive, state.current, state.previous, workspaces);
}

function stateWithFocus(state: ActivityState, current: string, previous: string, lastActive: LastActive[]): ActivityState {
  return makeActivityState(state.defs, state.defaultActivity, state.assignments, state.members, lastActive, current, previous, state.workspaces);
}

export function applyWorkspaces(state: ActivityState, workspaces: Workspace[]): ActivityState {
  const members: Membership[] = adoptAll(state, workspaces);
  const withWorkspaces: ActivityState = stateWithWorkspaces(state, members, workspaces);
  const matched22 = focusedWorkspace(workspaces);
  switch (matched22.tag) {
    case "WorkspaceMissing": {
      const token = matched22.token;
      return withWorkspaces;
    }
    case "WorkspaceFound": {
      const focused = matched22.workspace;
      const focusedActivity: string | null = membershipFor(members, focused.id);
      if ((focusedActivity == null)) {
        return withWorkspaces;
      } else {
        const changed: boolean = (focusedActivity !== withWorkspaces.current);
        return stateWithFocus(withWorkspaces, focusedActivity, (changed ? withWorkspaces.current : withWorkspaces.previous), putLastActive(withWorkspaces.lastActive, focusedActivity, focused.id));
      }
    }
  }
}

function activityTarget(state: ActivityState, workspaces: Workspace[], activity: string): WorkspaceLookup {
  const members: Workspace[] = membersOf(state, workspaces, activity);
  const lastId: number | null = lastActiveFor(state.lastActive, activity);
  if ((lastId == null)) {
    if ((members.length === 0)) {
      return makeWorkspaceMissing(false);
    } else {
      return makeWorkspaceFound(members[0]);
    }
  } else {
    let index: number = 0;
    loop23: while (true) {
      if ((index >= members.length)) {
        if ((members.length === 0)) {
          return makeWorkspaceMissing(false);
        } else {
          return makeWorkspaceFound(members[0]);
        }
      } else {
        const workspace: Workspace = members[index];
        if ((workspace.id === lastId)) {
          return makeWorkspaceFound(workspace);
        } else {
          [index] = [(index + 1)];
          continue loop23;
        }
      }
    }
  }
}

function nthMember(state: ActivityState, workspaces: Workspace[], ordinal: number): WorkspaceLookup {
  const members: Workspace[] = membersOf(state, workspaces, state.current);
  if ((members.length === 0)) {
    return makeWorkspaceMissing(false);
  } else {
    const bounded: number = Math.min(Math.max(0, (ordinal - 1)), (members.length - 1));
    return makeWorkspaceFound(members[bounded]);
  }
}

export function workspaceReference(workspace: Workspace): string {
  const name: string | null = workspace.name;
  if ((name == null)) {
    return (String(workspace.idx));
  } else {
    return name;
  }
}

function putAssignment(assignments: Assignment[], workspaceName: string, activity: string): Assignment[] {
  let index: number = 0;
  let found: boolean = false;
  let result: Assignment[] = [];
  loop24: while (true) {
    if ((index >= assignments.length)) {
      if (found) {
        return result;
      } else {
        return [...result, makeAssignment(workspaceName, activity)];
      }
    } else {
      const assignment: Assignment = assignments[index];
      if ((assignment.workspaceName === workspaceName)) {
        [index, found, result] = [(index + 1), true, [...result, makeAssignment(workspaceName, activity)]];
        continue loop24;
      } else {
        [index, found, result] = [(index + 1), found, [...result, assignment]];
        continue loop24;
      }
    }
  }
}

function stateWithMembers(state: ActivityState, members: Membership[]): ActivityState {
  return makeActivityState(state.defs, state.defaultActivity, state.assignments, members, state.lastActive, state.current, state.previous, state.workspaces);
}

function stateWithAssignments(state: ActivityState, assignments: Assignment[]): ActivityState {
  return makeActivityState(state.defs, state.defaultActivity, assignments, state.members, state.lastActive, state.current, state.previous, state.workspaces);
}

function assignState(state: ActivityState, workspace: Workspace, activity: string): ActivityState {
  const withMember: ActivityState = stateWithMembers(state, putMembership(state.members, workspace.id, activity));
  const assignedName: string | null = workspace.name;
  if ((assignedName == null)) {
    return withMember;
  } else {
    return stateWithAssignments(withMember, putAssignment(withMember.assignments, assignedName, activity));
  }
}

function firstActivitySeed(state: ActivityState, workspaces: Workspace[]): WorkspaceLookup {
  let index: number = 0;
  loop25: while (true) {
    if ((index >= workspaces.length)) {
      return makeWorkspaceMissing(false);
    } else {
      const workspace: Workspace = workspaces[index];
      if (((membershipFor(state.members, workspace.id) == null) && floatingP(workspaces, workspace))) {
        return makeWorkspaceFound(workspace);
      } else {
        [index] = [(index + 1)];
        continue loop25;
      }
    }
  }
}

function activitySwitchEffects(workspaces: Workspace[], workspace: Workspace, activity: string, moveP: boolean): ActivityEffect[] {
  const action: ActivityEffect = (moveP ? makeMoveColumnToWorkspace(workspace) : makeFocusWorkspace(workspace));
  if (floatingP(workspaces, workspace)) {
    return [makeNameWorkspace(workspace, activity), action];
  } else {
    return [action];
  }
}

function gotoOutcome(state: ActivityState, workspaces: Workspace[], activity: string, moveP: boolean): CommandOutcome {
  const matched26 = activityTarget(state, workspaces, activity);
  switch (matched26.tag) {
    case "WorkspaceFound": {
      const workspace = matched26.workspace;
      return makeCommandOutcome(state, activitySwitchEffects(workspaces, workspace, activity, moveP));
    }
    case "WorkspaceMissing": {
      const token = matched26.token;
      const matched27 = firstActivitySeed(state, workspaces);
      switch (matched27.tag) {
        case "WorkspaceMissing": {
          const nestedToken = matched27.token;
          return makeCommandOutcome(state, []);
        }
        case "WorkspaceFound": {
          const workspace = matched27.workspace;
          const assigned: ActivityState = assignState(state, workspace, activity);
          return makeCommandOutcome(assigned, (moveP ? [makeNameWorkspace(workspace, activity), makeReconcileBands(true), makePublishSnapshot(true), makeMoveColumnToWorkspace(workspace)] : [makeNameWorkspace(workspace, activity), makeReconcileBands(true), makePublishSnapshot(true), makeFocusWorkspace(workspace)]));
        }
      }
    }
  }
}

function assignOutcome(state: ActivityState, workspaces: Workspace[], activity: string): CommandOutcome {
  const matched28 = focusedWorkspace(workspaces);
  switch (matched28.tag) {
    case "WorkspaceMissing": {
      const token = matched28.token;
      return makeCommandOutcome(state, []);
    }
    case "WorkspaceFound": {
      const workspace = matched28.workspace;
      const assigned: ActivityState = assignState(state, workspace, activity);
      if ((workspace.name == null)) {
        return makeCommandOutcome(assigned, [makeReconcileBands(true), makePublishSnapshot(true)]);
      } else {
        return makeCommandOutcome(assigned, [makeReconcileBands(true), makePublishSnapshot(true), makePersistAssignments(assigned.assignments)]);
      }
    }
  }
}

export function applyCommand(state: ActivityState, workspaces: Workspace[], command: ActivityCommand): CommandOutcome {
  const matched29 = command;
  switch (matched29.tag) {
    case "Goto": {
      const activity = matched29.activity;
      return gotoOutcome(state, workspaces, activity, false);
    }
    case "MoveToActivity": {
      const activity = matched29.activity;
      return gotoOutcome(state, workspaces, activity, true);
    }
    case "Back": {
      const token = matched29.token;
      return gotoOutcome(state, workspaces, state.previous, false);
    }
    case "Here": {
      const ordinal = matched29.ordinal;
      const matched30 = nthMember(state, workspaces, ordinal);
      switch (matched30.tag) {
        case "WorkspaceMissing": {
          const token = matched30.token;
          return makeCommandOutcome(state, []);
        }
        case "WorkspaceFound": {
          const workspace = matched30.workspace;
          return makeCommandOutcome(state, [makeFocusWorkspace(workspace)]);
        }
      }
    }
    case "MoveHere": {
      const ordinal = matched29.ordinal;
      const matched31 = nthMember(state, workspaces, ordinal);
      switch (matched31.tag) {
        case "WorkspaceMissing": {
          const token = matched31.token;
          return makeCommandOutcome(state, []);
        }
        case "WorkspaceFound": {
          const workspace = matched31.workspace;
          return makeCommandOutcome(state, [makeMoveColumnToWorkspace(workspace)]);
        }
      }
    }
    case "Assign": {
      const activity = matched29.activity;
      return assignOutcome(state, workspaces, activity);
    }
  }
}
