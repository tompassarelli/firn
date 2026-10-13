import * as a from "./activity_core.ts";
import * as d from "./activity_driver.ts";


function workspace(seed: number, id: number, idx: number, name: string | null, window: number | null): a.Workspace {
  return a.makeWorkspace(id, idx, name, "DP-1", false, false, false, window);
}

function focusedWorkspace(seed: number, id: number, idx: number, name: string | null): a.Workspace {
  return a.makeWorkspace(id, idx, name, "DP-1", true, true, false, null);
}

function membershipActivity(seed: number, state: a.ActivityState, workspaceId: number): string | null {
  const members: a.Membership[] = state.members;
  let index: number = 0;
  loop1: while (true) {
    if ((index >= members.length)) {
      return null;
    } else {
      const entry: a.Membership = members[index];
      if ((entry.workspaceId === workspaceId)) {
        return entry.activity;
      } else {
        [index] = [(index + 1)];
        continue loop1;
      }
    }
  }
}

function persistentActivitySequenceP(seed: number): boolean {
  const defs: a.ActivityDef[] = [a.makeActivityDef((String("home") + String(((seed === 0) ? "" : seed))), (String("home") + String(((seed === 0) ? "" : seed))), [], []), a.makeActivityDef((String("gjoa") + String(((seed === 0) ? "" : seed))), (String("gjoa") + String(((seed === 0) ? "" : seed))), [], []), a.makeActivityDef((String("acme") + String(((seed === 0) ? "" : seed))), (String("acme") + String(((seed === 0) ? "" : seed))), [], [])];
  const base: a.ActivityState = a.makeActivityState(defs, (String("home") + String(((seed === 0) ? "" : seed))), [], [], [], (String("home") + String(((seed === 0) ? "" : seed))), (String("home") + String(((seed === 0) ? "" : seed))), []);
  const startWorkspaces: a.Workspace[] = [workspace(seed, 1, 1, (String("notes") + String(((seed === 0) ? "" : seed))), 10), workspace(seed, 2, 2, null, null)];
  const start: a.ActivityState = a.applyWorkspaces(base, startWorkspaces);
  const gjoaPlan: d.CommandPlan = d.planCommand(start, startWorkspaces, a.makeGoto((String("gjoa") + String(((seed === 0) ? "" : seed)))));
  const gjoaSteps: d.PlannedStep[] = gjoaPlan.steps;
  const gjoaWorkspaces: a.Workspace[] = [workspace(seed, 1, 1, (String("notes") + String(((seed === 0) ? "" : seed))), 10), focusedWorkspace(seed, 2, 2, (String("gjoa") + String(((seed === 0) ? "" : seed)))), workspace(seed, 3, 3, null, null)];
  const gjoaState: a.ActivityState = a.applyWorkspaces(gjoaPlan.state, gjoaWorkspaces);
  const acmePlan: d.CommandPlan = d.planCommand(gjoaState, gjoaWorkspaces, a.makeGoto((String("acme") + String(((seed === 0) ? "" : seed)))));
  const acmeSteps: d.PlannedStep[] = acmePlan.steps;
  const allWorkspaces: a.Workspace[] = [workspace(seed, 1, 1, (String("notes") + String(((seed === 0) ? "" : seed))), 10), workspace(seed, 2, 2, (String("gjoa") + String(((seed === 0) ? "" : seed))), null), focusedWorkspace(seed, 3, 3, (String("acme") + String(((seed === 0) ? "" : seed)))), workspace(seed, 4, 4, null, null)];
  const allState: a.ActivityState = a.applyWorkspaces(acmePlan.state, allWorkspaces);
  const backPlan: d.CommandPlan = d.planCommand(allState, allWorkspaces, a.makeGoto((String("gjoa") + String(((seed === 0) ? "" : seed)))));
  const backSteps: d.PlannedStep[] = backPlan.steps;
  const restarted: a.ActivityState = a.applyWorkspaces(a.makeActivityState(defs, (String("home") + String(((seed === 0) ? "" : seed))), [], [], [], (String("home") + String(((seed === 0) ? "" : seed))), (String("home") + String(((seed === 0) ? "" : seed))), []), allWorkspaces);
  const restartPlan: d.CommandPlan = d.planCommand(restarted, allWorkspaces, a.makeGoto((String("gjoa") + String(((seed === 0) ? "" : seed)))));
  const restartSteps: d.PlannedStep[] = restartPlan.steps;
  return (gjoaPlan.settled && (() => {
    const matched2 = gjoaSteps[0];
    switch (matched2.tag) {
      case "NameWorkspaceStep": {
        const reference = matched2.reference;
        const name = matched2.name;
        return ((reference === "2") && (name === (String("gjoa") + String(((seed === 0) ? "" : seed)))));
      }
      case "FocusStep": {
        const reference = matched2.reference;
        return false;
      }
      case "MoveColumnStep": {
        const reference = matched2.reference;
        return false;
      }
      case "ReorderStep": {
        const reference = matched2.reference;
        const id = matched2.id;
        const targetIndex = matched2.targetIndex;
        return false;
      }
      case "SnapshotStep": {
        const snapshot = matched2.snapshot;
        return false;
      }
      case "PersistStep": {
        const assignments = matched2.assignments;
        return false;
      }
    }
  })() && (membershipActivity(seed, gjoaState, 2) === (String("gjoa") + String(((seed === 0) ? "" : seed)))) && (membershipActivity(seed, gjoaState, 3) == null) && acmePlan.settled && (() => {
    const matched3 = acmeSteps[0];
    switch (matched3.tag) {
      case "NameWorkspaceStep": {
        const reference = matched3.reference;
        const name = matched3.name;
        return ((reference === "3") && (name === (String("acme") + String(((seed === 0) ? "" : seed)))));
      }
      case "FocusStep": {
        const reference = matched3.reference;
        return false;
      }
      case "MoveColumnStep": {
        const reference = matched3.reference;
        return false;
      }
      case "ReorderStep": {
        const reference = matched3.reference;
        const id = matched3.id;
        const targetIndex = matched3.targetIndex;
        return false;
      }
      case "SnapshotStep": {
        const snapshot = matched3.snapshot;
        return false;
      }
      case "PersistStep": {
        const assignments = matched3.assignments;
        return false;
      }
    }
  })() && (membershipActivity(seed, allState, 1) === (String("home") + String(((seed === 0) ? "" : seed)))) && (membershipActivity(seed, allState, 2) === (String("gjoa") + String(((seed === 0) ? "" : seed)))) && (membershipActivity(seed, allState, 3) === (String("acme") + String(((seed === 0) ? "" : seed)))) && (membershipActivity(seed, allState, 4) == null) && (() => {
    const matched4 = backSteps[0];
    switch (matched4.tag) {
      case "FocusStep": {
        const reference = matched4.reference;
        return (reference === (String("gjoa") + String(((seed === 0) ? "" : seed))));
      }
      case "MoveColumnStep": {
        const reference = matched4.reference;
        return false;
      }
      case "NameWorkspaceStep": {
        const reference = matched4.reference;
        const name = matched4.name;
        return false;
      }
      case "ReorderStep": {
        const reference = matched4.reference;
        const id = matched4.id;
        const targetIndex = matched4.targetIndex;
        return false;
      }
      case "SnapshotStep": {
        const snapshot = matched4.snapshot;
        return false;
      }
      case "PersistStep": {
        const assignments = matched4.assignments;
        return false;
      }
    }
  })() && (membershipActivity(seed, restarted, 1) === (String("home") + String(((seed === 0) ? "" : seed)))) && (membershipActivity(seed, restarted, 2) === (String("gjoa") + String(((seed === 0) ? "" : seed)))) && (membershipActivity(seed, restarted, 3) === (String("acme") + String(((seed === 0) ? "" : seed)))) && (membershipActivity(seed, restarted, 4) == null) && (() => {
    const matched5 = restartSteps[0];
    switch (matched5.tag) {
      case "FocusStep": {
        const reference = matched5.reference;
        return (reference === (String("gjoa") + String(((seed === 0) ? "" : seed))));
      }
      case "MoveColumnStep": {
        const reference = matched5.reference;
        return false;
      }
      case "NameWorkspaceStep": {
        const reference = matched5.reference;
        const name = matched5.name;
        return false;
      }
      case "ReorderStep": {
        const reference = matched5.reference;
        const id = matched5.id;
        const targetIndex = matched5.targetIndex;
        return false;
      }
      case "SnapshotStep": {
        const snapshot = matched5.snapshot;
        return false;
      }
      case "PersistStep": {
        const assignments = matched5.assignments;
        return false;
      }
    }
  })());
}

export function runScenarios(): number {
  if ((persistentActivitySequenceP(0))) {
    return 0;
  } else {
    console.log("FAIL activity_focus scenarios");
    return 1;
  }
}
