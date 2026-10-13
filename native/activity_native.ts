import * as a from "./activity_core.ts";
import * as d from "./activity_driver.ts";
import * as json from "./native_json.ts";
const activityHostCall = (operation: string, args: any): any => (globalThis as any)["activity_host_call"](operation, args);
const activityHostGet = (value: any, index: number): any => (globalThis as any)["activity_host_get"](value, index);






export type ReadTextBoundedResult = ReadTextBoundedOk | ReadTextBoundedError;
export type ReadTextBoundedOk = Readonly<{ tag: "ReadTextBoundedOk"; text: string; }>;
function makeReadTextBoundedOk(text: string): ReadTextBoundedOk { return { tag: "ReadTextBoundedOk", text }; }
export type ReadTextBoundedError = Readonly<{ tag: "ReadTextBoundedError"; errno: number; }>;
function makeReadTextBoundedError(errno: number): ReadTextBoundedError { return { tag: "ReadTextBoundedError", errno }; }

export type WriteTextAtomicResult = WriteTextAtomicOk | WriteTextAtomicError;
export type WriteTextAtomicOk = Readonly<{ tag: "WriteTextAtomicOk";  }>;
function makeWriteTextAtomicOk(): WriteTextAtomicOk { return { tag: "WriteTextAtomicOk",  }; }
export type WriteTextAtomicError = Readonly<{ tag: "WriteTextAtomicError"; errno: number; }>;
function makeWriteTextAtomicError(errno: number): WriteTextAtomicError { return { tag: "WriteTextAtomicError", errno }; }

export type MakeParentDirectoriesResult = MakeParentDirectoriesOk | MakeParentDirectoriesError;
export type MakeParentDirectoriesOk = Readonly<{ tag: "MakeParentDirectoriesOk";  }>;
function makeMakeParentDirectoriesOk(): MakeParentDirectoriesOk { return { tag: "MakeParentDirectoriesOk",  }; }
export type MakeParentDirectoriesError = Readonly<{ tag: "MakeParentDirectoriesError"; errno: number; }>;
function makeMakeParentDirectoriesError(errno: number): MakeParentDirectoriesError { return { tag: "MakeParentDirectoriesError", errno }; }

export type PathKindResult = PathKindOk | PathKindError;
export type PathKindOk = Readonly<{ tag: "PathKindOk"; kind: number; }>;
function makePathKindOk(kind: number): PathKindOk { return { tag: "PathKindOk", kind }; }
export type PathKindError = Readonly<{ tag: "PathKindError"; errno: number; }>;
function makePathKindError(errno: number): PathKindError { return { tag: "PathKindError", errno }; }

export type LockExclusiveResult = LockExclusiveOk | LockExclusiveError;
export type LockExclusiveOk = Readonly<{ tag: "LockExclusiveOk"; descriptor: number; }>;
function makeLockExclusiveOk(descriptor: number): LockExclusiveOk { return { tag: "LockExclusiveOk", descriptor }; }
export type LockExclusiveError = Readonly<{ tag: "LockExclusiveError"; errno: number; }>;
function makeLockExclusiveError(errno: number): LockExclusiveError { return { tag: "LockExclusiveError", errno }; }

export type CaptureResult = CaptureOk | CaptureError;
export type CaptureOk = Readonly<{ tag: "CaptureOk"; status: number; stdout: string; stderr: string; }>;
function makeCaptureOk(status: number, stdout: string, stderr: string): CaptureOk { return { tag: "CaptureOk", status, stdout, stderr }; }
export type CaptureError = Readonly<{ tag: "CaptureError"; errno: number; }>;
function makeCaptureError(errno: number): CaptureError { return { tag: "CaptureError", errno }; }

export type SpawnStdoutResult = SpawnStdoutOk | SpawnStdoutError;
export type SpawnStdoutOk = Readonly<{ tag: "SpawnStdoutOk"; pid: number; stdoutFd: number; }>;
function makeSpawnStdoutOk(pid: number, stdoutFd: number): SpawnStdoutOk { return { tag: "SpawnStdoutOk", pid, stdoutFd }; }
export type SpawnStdoutError = Readonly<{ tag: "SpawnStdoutError"; errno: number; }>;
function makeSpawnStdoutError(errno: number): SpawnStdoutError { return { tag: "SpawnStdoutError", errno }; }

export type ReadLineResult = ReadLineOk | ReadLineError;
export type ReadLineOk = Readonly<{ tag: "ReadLineOk"; line: string; eof: boolean; }>;
function makeReadLineOk(line: string, eof: boolean): ReadLineOk { return { tag: "ReadLineOk", line, eof }; }
export type ReadLineError = Readonly<{ tag: "ReadLineError"; errno: number; }>;
function makeReadLineError(errno: number): ReadLineError { return { tag: "ReadLineError", errno }; }

function hostEnv(name: string): string | null {
  return activityHostCall("env", [name]);
}

function hostStderr(text: string): null {
  const ignored: any = activityHostCall("stderr", [text]);
  return null;
}

function stdoutLine(text: string): null {
  const ignored: any = activityHostCall("stdout", [(String(text) + String("\n"))]);
  return null;
}

function hostReadTextBounded(path: string, limit: number): ReadTextBoundedResult {
  const result: any = activityHostCall("read-text-bounded", [path, limit]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makeReadTextBoundedOk(activityHostGet(result, 1));
  } else {
    return makeReadTextBoundedError(activityHostGet(result, 1));
  }
}

function hostWriteTextAtomic(path: string, text: string): WriteTextAtomicResult {
  const result: any = activityHostCall("write-text-atomic", [path, text]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makeWriteTextAtomicOk();
  } else {
    return makeWriteTextAtomicError(activityHostGet(result, 1));
  }
}

function hostMakeParentDirectories(path: string): MakeParentDirectoriesResult {
  const result: any = activityHostCall("make-parent-directories", [path]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makeMakeParentDirectoriesOk();
  } else {
    return makeMakeParentDirectoriesError(activityHostGet(result, 1));
  }
}

function hostPathKind(path: string): PathKindResult {
  const result: any = activityHostCall("path-kind", [path]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makePathKindOk(activityHostGet(result, 1));
  } else {
    return makePathKindError(activityHostGet(result, 1));
  }
}

function hostLockExclusive(path: string): LockExclusiveResult {
  const result: any = activityHostCall("lock-exclusive", [path]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makeLockExclusiveOk(activityHostGet(result, 1));
  } else {
    return makeLockExclusiveError(activityHostGet(result, 1));
  }
}

function hostCapture(argv: string[], input: string, limit: number): CaptureResult {
  const result: any = activityHostCall("capture", [argv, input, limit]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makeCaptureOk(activityHostGet(result, 1), activityHostGet(result, 2), activityHostGet(result, 3));
  } else {
    return makeCaptureError(activityHostGet(result, 1));
  }
}

function hostSpawnStdout(argv: string[]): SpawnStdoutResult {
  const result: any = activityHostCall("spawn-stdout", [argv]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makeSpawnStdoutOk(activityHostGet(result, 1), activityHostGet(result, 2));
  } else {
    return makeSpawnStdoutError(activityHostGet(result, 1));
  }
}

function hostReadLineDeadline(descriptor: number, limit: number, timeoutMs: number): ReadLineResult {
  const result: any = activityHostCall("read-line-deadline", [descriptor, limit, timeoutMs]);
  if ((activityHostGet(result, 0) === "ok")) {
    return makeReadLineOk(activityHostGet(result, 1), activityHostGet(result, 2));
  } else {
    return makeReadLineError(activityHostGet(result, 1));
  }
}

function hostInt(operation: string, args: any): number {
  return activityHostCall(operation, args);
}

function hostBool(operation: string, args: any): boolean {
  return activityHostCall(operation, args);
}

function hostUnlock(descriptor: number): null {
  const ignored: any = activityHostCall("unlock", [descriptor]);
  return null;
}

function hostSleep(milliseconds: number): null {
  const ignored: any = activityHostCall("sleep", [milliseconds]);
  return null;
}

function hostWallNanoseconds(): number {
  return hostInt("wall-nanoseconds", []);
}

function hostCurrentPid(): number {
  return hostInt("current-pid", []);
}

function hostAliveP(pid: number): boolean {
  return hostBool("alive", [pid]);
}

function hostSignal(pid: number, signal: number): number {
  return hostInt("signal", [pid, signal]);
}

function hostWaitNotAlive(pid: number, timeoutMs: number): number {
  return hostInt("wait-not-alive", [pid, timeoutMs]);
}

function hostFifoCreate(path: string): number {
  return hostInt("fifo-create", [path]);
}

function hostFifoOpenRead(path: string): number {
  return hostInt("fifo-open-read", [path]);
}

function hostFifoWriteDeadline(path: string, text: string, timeoutMs: number): number {
  return hostInt("fifo-write-deadline", [path, text, timeoutMs]);
}

function hostPollReadable(descriptors: number[], timeoutMs: number): number {
  return hostInt("poll-readable", [descriptors, timeoutMs]);
}

function hostClose(descriptor: number): number {
  return hostInt("close", [descriptor]);
}

function hostWait(pid: number): number {
  return hostInt("wait", [pid]);
}

const maxConfigBytes: number = 1048576;

const maxStateBytes: number = 16777216;

const maxCommandOutput: number = 16777216;

const maxLineBytes: number = 16777216;

const fifoWriteTimeoutMs: number = 500;

const pollTimeoutMs: number = 250;

const idlePollTimeoutMs: number = 60000;

const pollTimeoutStatus: number = -110;

const childStopTimeoutMs: number = 500;

const reconnectDelayMs: number = 2000;

const leaseRetryDelayMs: number = 25;

const leaseAttemptLimit: number = 80;

export type ActivityPaths = Readonly<{ runtimeDir: string; ctl: string; lease: string; pid: string; stateDir: string; state: string; assignments: string; defs: string; }>;
function makeActivityPaths(runtimeDir: string, ctl: string, lease: string, pid: string, stateDir: string, state: string, assignments: string, defs: string): ActivityPaths { return { runtimeDir, ctl, lease, pid, stateDir, state, assignments, defs }; }

export type StringVectorResult = StringVectorLoaded | StringVectorRejected;
export type StringVectorLoaded = Readonly<{ tag: "StringVectorLoaded"; values: string[]; }>;
function makeStringVectorLoaded(values: string[]): StringVectorLoaded { return { tag: "StringVectorLoaded", values }; }
export type StringVectorRejected = Readonly<{ tag: "StringVectorRejected"; message: string; }>;
function makeStringVectorRejected(message: string): StringVectorRejected { return { tag: "StringVectorRejected", message }; }

export type DefsResult = DefsLoaded | DefsRejected;
export type DefsLoaded = Readonly<{ tag: "DefsLoaded"; defs: a.ActivityDef[]; defaultActivity: string; }>;
function makeDefsLoaded(defs: a.ActivityDef[], defaultActivity: string): DefsLoaded { return { tag: "DefsLoaded", defs, defaultActivity }; }
export type DefsRejected = Readonly<{ tag: "DefsRejected"; message: string; }>;
function makeDefsRejected(message: string): DefsRejected { return { tag: "DefsRejected", message }; }

export type AssignmentsResult = AssignmentsLoaded | AssignmentsRejected;
export type AssignmentsLoaded = Readonly<{ tag: "AssignmentsLoaded"; assignments: a.Assignment[]; }>;
function makeAssignmentsLoaded(assignments: a.Assignment[]): AssignmentsLoaded { return { tag: "AssignmentsLoaded", assignments }; }
export type AssignmentsRejected = Readonly<{ tag: "AssignmentsRejected"; message: string; }>;
function makeAssignmentsRejected(message: string): AssignmentsRejected { return { tag: "AssignmentsRejected", message }; }

export type WorkspacesResult = WorkspacesLoaded | WorkspacesRejected;
export type WorkspacesLoaded = Readonly<{ tag: "WorkspacesLoaded"; workspaces: a.Workspace[]; }>;
function makeWorkspacesLoaded(workspaces: a.Workspace[]): WorkspacesLoaded { return { tag: "WorkspacesLoaded", workspaces }; }
export type WorkspacesRejected = Readonly<{ tag: "WorkspacesRejected"; message: string; }>;
function makeWorkspacesRejected(message: string): WorkspacesRejected { return { tag: "WorkspacesRejected", message }; }

export type ProcessResult = ProcessCompleted | ProcessRejected;
export type ProcessCompleted = Readonly<{ tag: "ProcessCompleted"; status: number; stdout: string; stderr: string; }>;
function makeProcessCompleted(status: number, stdout: string, stderr: string): ProcessCompleted { return { tag: "ProcessCompleted", status, stdout, stderr }; }
export type ProcessRejected = Readonly<{ tag: "ProcessRejected"; errno: number; }>;
function makeProcessRejected(errno: number): ProcessRejected { return { tag: "ProcessRejected", errno }; }

export type ParsedCommand = CommandLoaded | CommandIgnored;
export type CommandLoaded = Readonly<{ tag: "CommandLoaded"; command: a.ActivityCommand; }>;
function makeCommandLoaded(command: a.ActivityCommand): CommandLoaded { return { tag: "CommandLoaded", command }; }
export type CommandIgnored = Readonly<{ tag: "CommandIgnored"; token: boolean; }>;
function makeCommandIgnored(token: boolean): CommandIgnored { return { tag: "CommandIgnored", token }; }

export type ParsedEvent = EventWorkspaces | EventRescan | EventIgnored | EventRejected;
export type EventWorkspaces = Readonly<{ tag: "EventWorkspaces"; workspaces: a.Workspace[]; }>;
function makeEventWorkspaces(workspaces: a.Workspace[]): EventWorkspaces { return { tag: "EventWorkspaces", workspaces }; }
export type EventRescan = Readonly<{ tag: "EventRescan"; token: boolean; }>;
function makeEventRescan(token: boolean): EventRescan { return { tag: "EventRescan", token }; }
export type EventIgnored = Readonly<{ tag: "EventIgnored"; token: boolean; }>;
function makeEventIgnored(token: boolean): EventIgnored { return { tag: "EventIgnored", token }; }
export type EventRejected = Readonly<{ tag: "EventRejected"; message: string; }>;
function makeEventRejected(message: string): EventRejected { return { tag: "EventRejected", message }; }

export type ListEntry = Readonly<{ id: string; workspaceCount: number; }>;
function makeListEntry(id: string, workspaceCount: number): ListEntry { return { id, workspaceCount }; }

export type SnapshotView = Readonly<{ text: string; current: string; entries: ListEntry[]; }>;
function makeSnapshotView(text: string, current: string, entries: ListEntry[]): SnapshotView { return { text, current, entries }; }

export type SnapshotResult = SnapshotLoaded | SnapshotMissing;
export type SnapshotLoaded = Readonly<{ tag: "SnapshotLoaded"; snapshot: SnapshotView; }>;
function makeSnapshotLoaded(snapshot: SnapshotView): SnapshotLoaded { return { tag: "SnapshotLoaded", snapshot }; }
export type SnapshotMissing = Readonly<{ tag: "SnapshotMissing"; token: boolean; }>;
function makeSnapshotMissing(token: boolean): SnapshotMissing { return { tag: "SnapshotMissing", token }; }

export type LeaseResult = LeaseAcquired | LeaseRejected;
export type LeaseAcquired = Readonly<{ tag: "LeaseAcquired"; descriptor: number; }>;
function makeLeaseAcquired(descriptor: number): LeaseAcquired { return { tag: "LeaseAcquired", descriptor }; }
export type LeaseRejected = Readonly<{ tag: "LeaseRejected"; message: string; }>;
function makeLeaseRejected(message: string): LeaseRejected { return { tag: "LeaseRejected", message }; }

export type EventStreamResult = EventStreamStarted | EventStreamRejected;
export type EventStreamStarted = Readonly<{ tag: "EventStreamStarted"; pid: number; stdoutFd: number; }>;
function makeEventStreamStarted(pid: number, stdoutFd: number): EventStreamStarted { return { tag: "EventStreamStarted", pid, stdoutFd }; }
export type EventStreamRejected = Readonly<{ tag: "EventStreamRejected"; errno: number; }>;
function makeEventStreamRejected(errno: number): EventStreamRejected { return { tag: "EventStreamRejected", errno }; }

export type LineResult = LineLoaded | LineRejected;
export type LineLoaded = Readonly<{ tag: "LineLoaded"; line: string; eof: boolean; }>;
function makeLineLoaded(line: string, eof: boolean): LineLoaded { return { tag: "LineLoaded", line, eof }; }
export type LineRejected = Readonly<{ tag: "LineRejected"; errno: number; }>;
function makeLineRejected(errno: number): LineRejected { return { tag: "LineRejected", errno }; }

function stderrLine(message: string): null {
  return hostStderr((String(message) + String("\n")));
}

function environmentOr(name: string, fallback: string): string {
  const value: string | null = hostEnv(name);
  if ((value == null)) {
    return fallback;
  } else {
    return value;
  }
}

function activityPaths(defsOverride: string | null): ActivityPaths {
  const home: string = environmentOr("HOME", "/tmp");
  const runtimeRoot: string = environmentOr("XDG_RUNTIME_DIR", "/tmp");
  const stateRoot: string = environmentOr("XDG_STATE_HOME", (String(home) + String("/.local/state")));
  const configRoot: string = environmentOr("XDG_CONFIG_HOME", (String(home) + String("/.config")));
  const runtimeDir: string = (String(runtimeRoot) + String("/activity"));
  const stateDir: string = (String(stateRoot) + String("/activity"));
  return makeActivityPaths(runtimeDir, (String(runtimeDir) + String("/ctl")), (String(runtimeDir) + String("/lease")), (String(runtimeDir) + String("/pid")), stateDir, (String(stateDir) + String("/state.json")), (String(stateDir) + String("/assignments.json")), ((defsOverride == null) ? (String(configRoot) + String("/activity/activities.json")) : defsOverride));
}

function jsonContainerEnd(events: json.JsonEvent[], start: number): number {
  let index: number = start;
  let depth: number = 0;
  loop1: while (true) {
    if ((index >= events.length)) {
      return -1;
    } else {
      const event: json.JsonEvent = events[index];
      if (((event.tag === "JsonObjectStart") || (event.tag === "JsonArrayStart"))) {
        [index, depth] = [(index + 1), (depth + 1)];
        continue loop1;
      }
      if (((event.tag === "JsonObjectEnd") || (event.tag === "JsonArrayEnd"))) {
        if ((depth === 1)) {
          return (index + 1);
        } else {
          [index, depth] = [(index + 1), (depth - 1)];
          continue loop1;
        }
      }
      if (true) {
        [index, depth] = [(index + 1), depth];
        continue loop1;
      }
    }
  }
}

function jsonValueEnd(events: json.JsonEvent[], start: number): number {
  if (((start < 0) || (start >= events.length))) {
    return -1;
  } else {
    const event: json.JsonEvent = events[start];
    if (((event.tag === "JsonObjectStart") || (event.tag === "JsonArrayStart"))) {
      return jsonContainerEnd(events, start);
    }
    if (((event.tag === "JsonObjectEnd") || (event.tag === "JsonArrayEnd"))) {
      return -1;
    }
    if (true) {
      return (start + 1);
    }
  }
}

function jsonKeyValue(event: json.JsonEvent): string | null {
  const matched2 = event;
  switch (matched2.tag) {
    case "JsonKey": {
      const offset = matched2.offset;
      const value = matched2.value;
      return value;
    }
    case "JsonObjectStart": {
      const offset = matched2.offset;
      return null;
    }
    case "JsonObjectEnd": {
      const offset = matched2.offset;
      return null;
    }
    case "JsonArrayStart": {
      const offset = matched2.offset;
      return null;
    }
    case "JsonArrayEnd": {
      const offset = matched2.offset;
      return null;
    }
    case "JsonString": {
      const offset = matched2.offset;
      const value = matched2.value;
      return null;
    }
    case "JsonNumber": {
      const offset = matched2.offset;
      const lexeme = matched2.lexeme;
      return null;
    }
    case "JsonBoolean": {
      const offset = matched2.offset;
      const value = matched2.value;
      return null;
    }
    case "JsonNull": {
      const offset = matched2.offset;
      return null;
    }
  }
}

function jsonStringValue(event: json.JsonEvent): string | null {
  const matched3 = event;
  switch (matched3.tag) {
    case "JsonString": {
      const offset = matched3.offset;
      const value = matched3.value;
      return value;
    }
    case "JsonObjectStart": {
      const offset = matched3.offset;
      return null;
    }
    case "JsonObjectEnd": {
      const offset = matched3.offset;
      return null;
    }
    case "JsonArrayStart": {
      const offset = matched3.offset;
      return null;
    }
    case "JsonArrayEnd": {
      const offset = matched3.offset;
      return null;
    }
    case "JsonKey": {
      const offset = matched3.offset;
      const value = matched3.value;
      return null;
    }
    case "JsonNumber": {
      const offset = matched3.offset;
      const lexeme = matched3.lexeme;
      return null;
    }
    case "JsonBoolean": {
      const offset = matched3.offset;
      const value = matched3.value;
      return null;
    }
    case "JsonNull": {
      const offset = matched3.offset;
      return null;
    }
  }
}

function jsonNumberValue(event: json.JsonEvent): string | null {
  const matched4 = event;
  switch (matched4.tag) {
    case "JsonNumber": {
      const offset = matched4.offset;
      const lexeme = matched4.lexeme;
      return lexeme;
    }
    case "JsonObjectStart": {
      const offset = matched4.offset;
      return null;
    }
    case "JsonObjectEnd": {
      const offset = matched4.offset;
      return null;
    }
    case "JsonArrayStart": {
      const offset = matched4.offset;
      return null;
    }
    case "JsonArrayEnd": {
      const offset = matched4.offset;
      return null;
    }
    case "JsonKey": {
      const offset = matched4.offset;
      const value = matched4.value;
      return null;
    }
    case "JsonString": {
      const offset = matched4.offset;
      const value = matched4.value;
      return null;
    }
    case "JsonBoolean": {
      const offset = matched4.offset;
      const value = matched4.value;
      return null;
    }
    case "JsonNull": {
      const offset = matched4.offset;
      return null;
    }
  }
}

function jsonBooleanValue(event: json.JsonEvent): boolean | null {
  const matched5 = event;
  switch (matched5.tag) {
    case "JsonBoolean": {
      const offset = matched5.offset;
      const value = matched5.value;
      return value;
    }
    case "JsonObjectStart": {
      const offset = matched5.offset;
      return null;
    }
    case "JsonObjectEnd": {
      const offset = matched5.offset;
      return null;
    }
    case "JsonArrayStart": {
      const offset = matched5.offset;
      return null;
    }
    case "JsonArrayEnd": {
      const offset = matched5.offset;
      return null;
    }
    case "JsonKey": {
      const offset = matched5.offset;
      const value = matched5.value;
      return null;
    }
    case "JsonString": {
      const offset = matched5.offset;
      const value = matched5.value;
      return null;
    }
    case "JsonNumber": {
      const offset = matched5.offset;
      const lexeme = matched5.lexeme;
      return null;
    }
    case "JsonNull": {
      const offset = matched5.offset;
      return null;
    }
  }
}

function jsonObjectFieldIndex(events: json.JsonEvent[], start: number, wanted: string): number | null {
  if (((start < 0) || (start >= events.length) || !((events[start].tag === "JsonObjectStart")))) {
    return null;
  } else {
    const end: number = jsonValueEnd(events, start);
    if ((end < 0)) {
      return null;
    } else {
      let index: number = (start + 1);
      loop6: while (true) {
        if ((index >= (end - 1))) {
          return null;
        } else {
          const event: json.JsonEvent = events[index];
          const key: string | null = jsonKeyValue(event);
          if ((key == null)) {
            return null;
          } else {
            const valueIndex: number = (index + 1);
            const next: number = jsonValueEnd(events, valueIndex);
            const field: string = key;
            if ((next < 0)) {
              return null;
            } else {
              if ((field === wanted)) {
                return valueIndex;
              } else {
                [index] = [next];
                continue loop6;
              }
            }
          }
        }
      }
    }
  }
}

function jsonStringAt(events: json.JsonEvent[], index: number | null): string | null {
  if ((index == null)) {
    return null;
  } else {
    return jsonStringValue(events[index]);
  }
}

function jsonIntAt(events: json.JsonEvent[], index: number | null): number | null {
  if ((index == null)) {
    return null;
  } else {
    const lexeme: string | null = jsonNumberValue(events[index]);
    if ((lexeme == null)) {
      return null;
    } else {
      return parseInt(lexeme, 10);
    }
  }
}

function jsonBoolAt(events: json.JsonEvent[], index: number | null, fallback: boolean): boolean {
  if ((index == null)) {
    return fallback;
  } else {
    const value: boolean | null = jsonBooleanValue(events[index]);
    if ((value == null)) {
      return fallback;
    } else {
      return value;
    }
  }
}

function jsonNullableStringAt(events: json.JsonEvent[], index: number | null): string | null {
  if ((index == null)) {
    return null;
  } else {
    return jsonStringValue(events[index]);
  }
}

function workspaceObject(events: json.JsonEvent[], start: number): a.Workspace | null {
  const id: number | null = jsonIntAt(events, jsonObjectFieldIndex(events, start, "id"));
  const idx: number | null = jsonIntAt(events, jsonObjectFieldIndex(events, start, "idx"));
  const output: string | null = jsonStringAt(events, jsonObjectFieldIndex(events, start, "output"));
  if (((id == null) || (idx == null) || (output == null))) {
    return null;
  } else {
    return a.makeWorkspace(id, idx, jsonNullableStringAt(events, jsonObjectFieldIndex(events, start, "name")), output, jsonBoolAt(events, jsonObjectFieldIndex(events, start, "is_focused"), false), jsonBoolAt(events, jsonObjectFieldIndex(events, start, "is_active"), false), jsonBoolAt(events, jsonObjectFieldIndex(events, start, "is_urgent"), false), jsonIntAt(events, jsonObjectFieldIndex(events, start, "active_window_id")));
  }
}

function workspacesArray(events: json.JsonEvent[], start: number): WorkspacesResult {
  if (((start < 0) || (start >= events.length) || !((events[start].tag === "JsonArrayStart")))) {
    return makeWorkspacesRejected("expected a workspace array");
  } else {
    const end: number = jsonValueEnd(events, start);
    if ((end < 0)) {
      return makeWorkspacesRejected("unterminated workspace array");
    } else {
      let index: number = (start + 1);
      let result: a.Workspace[] = [];
      loop7: while (true) {
        if ((index === (end - 1))) {
          return makeWorkspacesLoaded(result);
        } else {
          const next: number = jsonValueEnd(events, index);
          const workspace: a.Workspace | null = workspaceObject(events, index);
          if (((next < 0) || (workspace == null))) {
            return makeWorkspacesRejected("invalid workspace object");
          } else {
            [index, result] = [next, [...result, workspace]];
            continue loop7;
          }
        }
      }
    }
  }
}

function parseWorkspacesJson(text: string): WorkspacesResult {
  const matched8 = json.decode(text);
  switch (matched8.tag) {
    case "JsonDecodeError": {
      const offset = matched8.offset;
      const message = matched8.message;
      return makeWorkspacesRejected((String(offset) + String(":") + String(message)));
    }
    case "JsonDecoded": {
      const events = matched8.events;
      if (events.length === 0) {
        return makeWorkspacesRejected("expected a workspace array");
      } else {
        return workspacesArray(events, 0);
      }
    }
  }
}

function parseEventJson(text: string): ParsedEvent {
  const matched9 = json.decode(text);
  switch (matched9.tag) {
    case "JsonDecodeError": {
      const offset = matched9.offset;
      const message = matched9.message;
      return makeEventRejected((String(offset) + String(":") + String(message)));
    }
    case "JsonDecoded": {
      const events = matched9.events;
      if ((events.length === 0 || !(((events[0] ?? null).tag === "JsonObjectStart")))) {
        return makeEventRejected("expected an event object");
      } else {
        const changed: number | null = jsonObjectFieldIndex(events, 0, "WorkspacesChanged");
        const activated: number | null = jsonObjectFieldIndex(events, 0, "WorkspaceActivated");
        const activeWindow: number | null = jsonObjectFieldIndex(events, 0, "WorkspaceActiveWindowChanged");
        if ((changed != null)) {
          const workspaceIndex: number | null = jsonObjectFieldIndex(events, changed, "workspaces");
          if ((workspaceIndex == null)) {
            return makeEventRejected("WorkspacesChanged has no workspaces");
          } else {
            const matched10 = workspacesArray(events, workspaceIndex);
            switch (matched10.tag) {
              case "WorkspacesLoaded": {
                const workspaces = matched10.workspaces;
                return makeEventWorkspaces(workspaces);
              }
              case "WorkspacesRejected": {
                const message = matched10.message;
                return makeEventRejected(message);
              }
            }
          }
        }
        if (((activated != null) || (activeWindow != null))) {
          return makeEventRescan(true);
        }
        if (true) {
          return makeEventIgnored(true);
        }
      }
    }
  }
}

function jsonStringVectorAt(events: json.JsonEvent[], index: number | null): StringVectorResult {
  if ((index == null)) {
    return makeStringVectorLoaded([]);
  } else {
    if (!((events[index].tag === "JsonArrayStart"))) {
      return makeStringVectorRejected("expected a string array");
    } else {
      const end: number = jsonValueEnd(events, index);
      if ((end < 0)) {
        return makeStringVectorRejected("unterminated string array");
      } else {
        let at: number = (index + 1);
        let result: string[] = [];
        loop11: while (true) {
          if ((at === (end - 1))) {
            return makeStringVectorLoaded(result);
          } else {
            const event: json.JsonEvent = events[at];
            const value: string | null = jsonStringValue(event);
            if ((value != null)) {
              [at, result] = [(at + 1), [...result, value]];
              continue loop11;
            } else {
              return makeStringVectorRejected("activity bindings must be strings");
            }
          }
        }
      }
    }
  }
}

function activityDefinition(events: json.JsonEvent[], start: number): a.ActivityDef | null {
  const id: string | null = jsonStringAt(events, jsonObjectFieldIndex(events, start, "id"));
  const label: string | null = jsonNullableStringAt(events, jsonObjectFieldIndex(events, start, "label"));
  if ((id == null)) {
    return null;
  } else {
    const matched12 = jsonStringVectorAt(events, jsonObjectFieldIndex(events, start, "bind_names"));
    switch (matched12.tag) {
      case "StringVectorRejected": {
        const message = matched12.message;
        return null;
      }
      case "StringVectorLoaded": {
        const names = matched12.values;
        const matched13 = jsonStringVectorAt(events, jsonObjectFieldIndex(events, start, "bind_prefixes"));
        switch (matched13.tag) {
          case "StringVectorRejected": {
            const message = matched13.message;
            return null;
          }
          case "StringVectorLoaded": {
            const prefixes = matched13.values;
            return a.makeActivityDef(id, label, names, prefixes);
          }
        }
      }
    }
  }
}

function activityDefinitions(events: json.JsonEvent[], start: number): DefsResult {
  if (((start < 0) || (start >= events.length) || !((events[start].tag === "JsonArrayStart")))) {
    return makeDefsRejected("activities must be an array");
  } else {
    const end: number = jsonValueEnd(events, start);
    if ((end < 0)) {
      return makeDefsRejected("unterminated activities array");
    } else {
      let index: number = (start + 1);
      let result: a.ActivityDef[] = [];
      loop14: while (true) {
        if ((index === (end - 1))) {
          if (result.length === 0) {
            return makeDefsRejected("activities must not be empty");
          } else {
            return makeDefsLoaded(result, "");
          }
        } else {
          const next: number = jsonValueEnd(events, index);
          const definition: a.ActivityDef | null = activityDefinition(events, index);
          if (((next < 0) || (definition == null))) {
            return makeDefsRejected("invalid activity definition");
          } else {
            [index, result] = [next, [...result, definition]];
            continue loop14;
          }
        }
      }
    }
  }
}

function definitionIds(defs: a.ActivityDef[]): string[] {
  let index: number = 0;
  let result: string[] = [];
  loop15: while (true) {
    if ((index >= defs.length)) {
      return result;
    } else {
      [index, result] = [(index + 1), [...result, defs[index].id]];
      continue loop15;
    }
  }
}

function parseDefs(text: string): DefsResult {
  const matched16 = json.decode(text);
  switch (matched16.tag) {
    case "JsonDecodeError": {
      const offset = matched16.offset;
      const message = matched16.message;
      return makeDefsRejected((String(offset) + String(":") + String(message)));
    }
    case "JsonDecoded": {
      const events = matched16.events;
      if ((events.length === 0 || !(((events[0] ?? null).tag === "JsonObjectStart")) || (jsonValueEnd(events, 0) !== events.length))) {
        return makeDefsRejected("expected an activity definition object");
      } else {
        const defaultActivity: string | null = jsonStringAt(events, jsonObjectFieldIndex(events, 0, "default"));
        const definitionsIndex: number | null = jsonObjectFieldIndex(events, 0, "activities");
        if (((defaultActivity == null) || (definitionsIndex == null))) {
          return makeDefsRejected("activity definitions require default and activities");
        } else {
          const matched17 = activityDefinitions(events, definitionsIndex);
          switch (matched17.tag) {
            case "DefsRejected": {
              const message = matched17.message;
              return makeDefsRejected(message);
            }
            case "DefsLoaded": {
              const defs = matched17.defs;
              const ignoredDefault = matched17.defaultActivity;
              if (a.stringMemberP(definitionIds(defs), defaultActivity)) {
                return makeDefsLoaded(defs, defaultActivity);
              } else {
                return makeDefsRejected("default must name an activity");
              }
            }
          }
        }
      }
    }
  }
}

function parseAssignmentsEvents(events: json.JsonEvent[]): AssignmentsResult {
  if ((events.length === 0 || !(((events[0] ?? null).tag === "JsonObjectStart")))) {
    return makeAssignmentsRejected("expected an assignment object");
  } else {
    const end: number = jsonValueEnd(events, 0);
    if ((end !== events.length)) {
      return makeAssignmentsRejected("invalid assignment object");
    } else {
      let index: number = 1;
      let result: a.Assignment[] = [];
      loop18: while (true) {
        if ((index === (end - 1))) {
          return makeAssignmentsLoaded(result);
        } else {
          if (((index + 1) > (end - 2))) {
            return makeAssignmentsRejected("assignment object has no value");
          } else {
            const nameEvent: json.JsonEvent = events[index];
            const activityEvent: json.JsonEvent = events[(index + 1)];
            const name: string | null = jsonKeyValue(nameEvent);
            const activity: string | null = jsonStringValue(activityEvent);
            if ((name == null)) {
              return makeAssignmentsRejected("assignment workspace name must be a string");
            }
            if ((activity == null)) {
              return makeAssignmentsRejected("assignment activity must be a string");
            }
            if (true) {
              [index, result] = [(index + 2), [...result, a.makeAssignment(name, activity)]];
              continue loop18;
            }
          }
        }
      }
    }
  }
}

function parseAssignments(text: string): AssignmentsResult {
  const matched19 = json.decode(text);
  switch (matched19.tag) {
    case "JsonDecodeError": {
      const offset = matched19.offset;
      const message = matched19.message;
      return makeAssignmentsRejected((String(offset) + String(":") + String(message)));
    }
    case "JsonDecoded": {
      const events = matched19.events;
      return parseAssignmentsEvents(events);
    }
  }
}

function loadDefs(path: string): DefsResult {
  const matched20 = hostReadTextBounded(path, maxConfigBytes);
  switch (matched20.tag) {
    case "ReadTextBoundedOk": {
      const text = matched20.text;
      return parseDefs(text);
    }
    case "ReadTextBoundedError": {
      const errno = matched20.errno;
      return makeDefsRejected((String("cannot read definitions: errno ") + String(errno)));
    }
  }
}

function loadAssignments(path: string): AssignmentsResult {
  const matched21 = hostReadTextBounded(path, maxConfigBytes);
  switch (matched21.tag) {
    case "ReadTextBoundedOk": {
      const text = matched21.text;
      return parseAssignments(text);
    }
    case "ReadTextBoundedError": {
      const errno = matched21.errno;
      if ((errno === 2)) {
        return makeAssignmentsLoaded([]);
      } else {
        return makeAssignmentsRejected((String("cannot read assignments: errno ") + String(errno)));
      }
    }
  }
}

function assignmentText(assignments: a.Assignment[]): string {
  const events: json.JsonEvent[] = (() => {
    let index: number = 0;
    let result: json.JsonEvent[] = [({ tag: "JsonObjectStart", offset: 0 } as json.JsonEvent)];
    loop22: while (true) {
      if ((index >= assignments.length)) {
        return [...result, ({ tag: "JsonObjectEnd", offset: 0 } as json.JsonEvent)];
      } else {
        const assignment: a.Assignment = assignments[index];
        [index, result] = [(index + 1), [...result, ({ tag: "JsonKey", offset: 0, value: assignment.workspaceName } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: assignment.activity } as json.JsonEvent)]];
        continue loop22;
      }
    }
  })();
  const matched23 = json.encode(events);
  switch (matched23.tag) {
    case "JsonEncoded": {
      const text = matched23.text;
      return (String(text) + String("\n"));
    }
    case "JsonEncodeError": {
      const eventIndex = matched23.eventIndex;
      const message = matched23.message;
      return "";
    }
  }
}

function persistAssignments(path: string, assignments: a.Assignment[]): number {
  const matched24 = hostWriteTextAtomic(path, assignmentText(assignments));
  switch (matched24.tag) {
    case "WriteTextAtomicOk": {
      return 0;
    }
    case "WriteTextAtomicError": {
      const errno = matched24.errno;
      stderrLine((String("activity daemon: cannot write assignments: errno ") + String(errno)));
      return 1;
    }
  }
}

function workspaceJsonEvents(workspace: a.Workspace): json.JsonEvent[] {
  const name: string | null = workspace.name;
  const events: json.JsonEvent[] = [];
  return [...events, ({ tag: "JsonObjectStart", offset: 0 } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "id" } as json.JsonEvent), ({ tag: "JsonNumber", offset: 0, lexeme: (String(workspace.id)) } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "idx" } as json.JsonEvent), ({ tag: "JsonNumber", offset: 0, lexeme: (String(workspace.idx)) } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "name" } as json.JsonEvent), ((name == null) ? ({ tag: "JsonNull", offset: 0 } as json.JsonEvent) : ({ tag: "JsonString", offset: 0, value: name } as json.JsonEvent)), ({ tag: "JsonKey", offset: 0, value: "output" } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: workspace.output } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "focused" } as json.JsonEvent), ({ tag: "JsonBoolean", offset: 0, value: workspace.focused } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "active" } as json.JsonEvent), ({ tag: "JsonBoolean", offset: 0, value: workspace.active } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "urgent" } as json.JsonEvent), ({ tag: "JsonBoolean", offset: 0, value: workspace.urgent } as json.JsonEvent), ({ tag: "JsonObjectEnd", offset: 0 } as json.JsonEvent)];
}

function workspacesJsonEvents(workspaces: a.Workspace[]): json.JsonEvent[] {
  const emptyEvents: json.JsonEvent[] = [];
  let index: number = 0;
  let events: json.JsonEvent[] = [...emptyEvents, ({ tag: "JsonArrayStart", offset: 0 } as json.JsonEvent)];
  loop25: while (true) {
    if ((index >= workspaces.length)) {
      return [...events, ({ tag: "JsonArrayEnd", offset: 0 } as json.JsonEvent)];
    } else {
      [index, events] = [(index + 1), [...events, ...workspaceJsonEvents(workspaces[index])]];
      continue loop25;
    }
  }
}

function activityJsonEvents(state: a.ActivityState, workspaces: a.Workspace[], definition: a.ActivityDef): json.JsonEvent[] {
  const id: string = definition.id;
  const label: string | null = definition.label;
  const lastActive: number | null = a.lastActiveFor(state.lastActive, id);
  const members: a.Workspace[] = a.membersOf(state, workspaces, id);
  const events: json.JsonEvent[] = [];
  return [...[...events, ({ tag: "JsonObjectStart", offset: 0 } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "id" } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: id } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "label" } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: ((label == null) ? id : label) } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "last_active" } as json.JsonEvent), ((lastActive == null) ? ({ tag: "JsonNull", offset: 0 } as json.JsonEvent) : ({ tag: "JsonNumber", offset: 0, lexeme: (String(lastActive)) } as json.JsonEvent)), ({ tag: "JsonKey", offset: 0, value: "workspaces" } as json.JsonEvent)], ...[...workspacesJsonEvents(members), ({ tag: "JsonObjectEnd", offset: 0 } as json.JsonEvent)]];
}

function activitiesJsonEvents(state: a.ActivityState, workspaces: a.Workspace[]): json.JsonEvent[] {
  const definitions: a.ActivityDef[] = state.defs;
  const emptyEvents: json.JsonEvent[] = [];
  let index: number = 0;
  let events: json.JsonEvent[] = [...emptyEvents, ({ tag: "JsonArrayStart", offset: 0 } as json.JsonEvent)];
  loop26: while (true) {
    if ((index >= definitions.length)) {
      return [...events, ({ tag: "JsonArrayEnd", offset: 0 } as json.JsonEvent)];
    } else {
      [index, events] = [(index + 1), [...events, ...activityJsonEvents(state, workspaces, definitions[index])]];
      continue loop26;
    }
  }
}

function snapshotEvents(state: a.ActivityState, workspaces: a.Workspace[]): json.JsonEvent[] {
  const generatedAt: number = Math.trunc(hostWallNanoseconds() / 1000000);
  const events: json.JsonEvent[] = [];
  const prefix: json.JsonEvent[] = [...events, ({ tag: "JsonObjectStart", offset: 0 } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "current" } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: state.current } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "previous" } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: state.previous } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "generated_at" } as json.JsonEvent), ({ tag: "JsonNumber", offset: 0, lexeme: (String(generatedAt)) } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "activities" } as json.JsonEvent)];
  const withActivities: json.JsonEvent[] = [...prefix, ...activitiesJsonEvents(state, workspaces)];
  const withFloatingKey: json.JsonEvent[] = [...withActivities, ({ tag: "JsonKey", offset: 0, value: "floating" } as json.JsonEvent)];
  return [...withFloatingKey, ...[...workspacesJsonEvents(a.floatsOf(state, workspaces)), ({ tag: "JsonObjectEnd", offset: 0 } as json.JsonEvent)]];
}

function writeSnapshot(path: string, state: a.ActivityState, workspaces: a.Workspace[]): number {
  const matched27 = json.encode(snapshotEvents(state, workspaces));
  switch (matched27.tag) {
    case "JsonEncodeError": {
      const eventIndex = matched27.eventIndex;
      const message = matched27.message;
      stderrLine((String("activity daemon: cannot encode snapshot: ") + String(message)));
      return 1;
    }
    case "JsonEncoded": {
      const text = matched27.text;
      const matched28 = hostWriteTextAtomic(path, (String(text) + String("\n")));
      switch (matched28.tag) {
        case "WriteTextAtomicOk": {
          return 0;
        }
        case "WriteTextAtomicError": {
          const errno = matched28.errno;
          stderrLine((String("activity daemon: cannot write snapshot: errno ") + String(errno)));
          return 1;
        }
      }
    }
  }
}

function capture(argv: string[]): ProcessResult {
  const matched29 = hostCapture(argv, "", maxCommandOutput);
  switch (matched29.tag) {
    case "CaptureOk": {
      const status = matched29.status;
      const stdout = matched29.stdout;
      const stderr = matched29.stderr;
      return makeProcessCompleted(status, stdout, stderr);
    }
    case "CaptureError": {
      const errno = matched29.errno;
      return makeProcessRejected(errno);
    }
  }
}

function niriWorkspaces(): WorkspacesResult {
  const matched30 = capture(["niri", "msg", "--json", "workspaces"]);
  switch (matched30.tag) {
    case "ProcessRejected": {
      const errno = matched30.errno;
      return makeWorkspacesRejected((String("cannot start niri: errno ") + String(errno)));
    }
    case "ProcessCompleted": {
      const status = matched30.status;
      const stdout = matched30.stdout;
      const stderr = matched30.stderr;
      if ((status === 0)) {
        return parseWorkspacesJson(stdout);
      } else {
        return makeWorkspacesRejected((String("niri exited ") + String(status)));
      }
    }
  }
}

function niriAction(args: string[]): boolean {
  const matched31 = capture([...["niri", "msg", "action"], ...args]);
  switch (matched31.tag) {
    case "ProcessRejected": {
      const errno = matched31.errno;
      return false;
    }
    case "ProcessCompleted": {
      const status = matched31.status;
      const stdout = matched31.stdout;
      const stderr = matched31.stderr;
      return (status === 0);
    }
  }
}

function executeReorderSteps(moves: a.WorkspaceMove[]): boolean {
  let index: number = 0;
  let succeeded: boolean = true;
  loop32: while (true) {
    if ((index >= moves.length)) {
      return succeeded;
    } else {
      const move: a.WorkspaceMove = moves[index];
      const workspace: a.Workspace = move.workspace;
      const ok: boolean = niriAction(["move-workspace-to-index", "--reference", a.workspaceReference(workspace), (String(move.targetIndex))]);
      [index, succeeded] = [(index + 1), (succeeded && ok)];
      continue loop32;
    }
  }
}

function applyWorkspaceRecord(paths: ActivityPaths, state: a.ActivityState, workspaces: a.Workspace[]): a.ActivityState {
  const applied: a.ActivityState = a.applyWorkspaces(state, workspaces);
  const outcome: d.BandOutcome = d.reconcileBands(applied, workspaces, d.defaultBandLimit(workspaces));
  const moves: a.WorkspaceMove[] = d.bandMoves(outcome);
  const modelled: a.Workspace[] = d.bandWorkspaces(outcome);
  const movesOk: boolean = executeReorderSteps(moves);
  const recorded: a.ActivityState = a.applyWorkspaces(applied, modelled);
  (!(d.bandSettledP(outcome)) ? stderrLine("activity daemon: band reconciliation limit reached") : null);
  (!(movesOk) ? stderrLine("activity daemon: niri workspace reorder failed") : null);
  writeSnapshot(paths.state, recorded, modelled);
  return recorded;
}

function rescanState(paths: ActivityPaths, state: a.ActivityState): a.ActivityState {
  const matched33 = niriWorkspaces();
  switch (matched33.tag) {
    case "WorkspacesRejected": {
      const message = matched33.message;
      stderrLine((String("activity daemon: ") + String(message)));
      return state;
    }
    case "WorkspacesLoaded": {
      const workspaces = matched33.workspaces;
      return applyWorkspaceRecord(paths, state, workspaces);
    }
  }
}

function parseCommandJson(text: string): ParsedCommand {
  const matched34 = json.decode(text);
  switch (matched34.tag) {
    case "JsonDecodeError": {
      const offset = matched34.offset;
      const message = matched34.message;
      return makeCommandIgnored(true);
    }
    case "JsonDecoded": {
      const events = matched34.events;
      if ((events.length === 0 || !(((events[0] ?? null).tag === "JsonObjectStart")))) {
        return makeCommandIgnored(true);
      } else {
        const command: string | null = jsonStringAt(events, jsonObjectFieldIndex(events, 0, "cmd"));
        const activity: string | null = jsonStringAt(events, jsonObjectFieldIndex(events, 0, "activity"));
        const ordinal: number | null = jsonIntAt(events, jsonObjectFieldIndex(events, 0, "n"));
        if (((command === "goto") && (activity != null))) {
          return makeCommandLoaded(a.makeGoto(activity));
        }
        if (((command === "move-to-activity") && (activity != null))) {
          return makeCommandLoaded(a.makeMoveToActivity(activity));
        }
        if ((command === "back")) {
          return makeCommandLoaded(a.makeBack(true));
        }
        if ((command === "here")) {
          return makeCommandLoaded(a.makeHere(((ordinal == null) ? 1 : ordinal)));
        }
        if ((command === "move-here")) {
          return makeCommandLoaded(a.makeMoveHere(((ordinal == null) ? 1 : ordinal)));
        }
        if (((command === "assign") && (activity != null))) {
          return makeCommandLoaded(a.makeAssign(activity));
        }
        if (true) {
          return makeCommandIgnored(true);
        }
      }
    }
  }
}

function executePlanSteps(paths: ActivityPaths, plan: d.CommandPlan): null {
  const steps: d.PlannedStep[] = plan.steps;
  let index: number = 0;
  loop35: while (true) {
    if ((index >= steps.length)) {
      return null;
    } else {
      const step: d.PlannedStep = steps[index];
      (() => {
        const matched36 = step;
        switch (matched36.tag) {
          case "FocusStep": {
            const reference = matched36.reference;
            if (niriAction(["focus-workspace", reference])) {
              return null;
            } else {
              return stderrLine("activity daemon: niri focus failed");
            }
          }
          case "MoveColumnStep": {
            const reference = matched36.reference;
            if (niriAction(["move-column-to-workspace", reference])) {
              return null;
            } else {
              return stderrLine("activity daemon: niri column move failed");
            }
          }
          case "NameWorkspaceStep": {
            const reference = matched36.reference;
            const name = matched36.name;
            if (niriAction(["set-workspace-name", name, "--workspace", reference])) {
              return null;
            } else {
              return stderrLine("activity daemon: niri workspace naming failed");
            }
          }
          case "ReorderStep": {
            const reference = matched36.reference;
            const id = matched36.id;
            const targetIndex = matched36.targetIndex;
            if (niriAction(["move-workspace-to-index", "--reference", reference, (String(targetIndex))])) {
              return null;
            } else {
              return stderrLine("activity daemon: niri workspace reorder failed");
            }
          }
          case "SnapshotStep": {
            const snapshot = matched36.snapshot;
            writeSnapshot(paths.state, plan.state, plan.workspaces);
            return null;
          }
          case "PersistStep": {
            const assignments = matched36.assignments;
            persistAssignments(paths.assignments, assignments);
            return null;
          }
        }
      })();
      [index] = [(index + 1)];
      continue loop35;
    }
  }
}

function handleCommand(paths: ActivityPaths, state: a.ActivityState, line: string): a.ActivityState {
  const matched37 = parseCommandJson(line);
  switch (matched37.tag) {
    case "CommandIgnored": {
      const token = matched37.token;
      return state;
    }
    case "CommandLoaded": {
      const command = matched37.command;
      const matched38 = niriWorkspaces();
      switch (matched38.tag) {
        case "WorkspacesRejected": {
          const message = matched38.message;
          stderrLine((String("activity daemon: ") + String(message)));
          return state;
        }
        case "WorkspacesLoaded": {
          const workspaces = matched38.workspaces;
          const plan: d.CommandPlan = d.planCommand(state, workspaces, command);
          (!(plan.settled) ? stderrLine("activity daemon: band reconciliation limit reached") : null);
          executePlanSteps(paths, plan);
          return plan.state;
        }
      }
    }
  }
}

function handleEvent(paths: ActivityPaths, state: a.ActivityState, line: string): a.ActivityState {
  const matched39 = parseEventJson(line);
  switch (matched39.tag) {
    case "EventWorkspaces": {
      const workspaces = matched39.workspaces;
      return applyWorkspaceRecord(paths, state, workspaces);
    }
    case "EventRescan": {
      const token = matched39.token;
      return rescanState(paths, state);
    }
    case "EventIgnored": {
      const token = matched39.token;
      return state;
    }
    case "EventRejected": {
      const message = matched39.message;
      stderrLine((String("activity daemon: invalid niri event: ") + String(message)));
      return state;
    }
  }
}

function makeParent(path: string): number {
  const matched40 = hostMakeParentDirectories(path);
  switch (matched40.tag) {
    case "MakeParentDirectoriesOk": {
      return 0;
    }
    case "MakeParentDirectoriesError": {
      const errno = matched40.errno;
      return (0 - errno);
    }
  }
}

function takeoverOwner(pidPath: string): number {
  const matched41 = hostReadTextBounded(pidPath, 64);
  switch (matched41.tag) {
    case "ReadTextBoundedError": {
      const errno = matched41.errno;
      return 0;
    }
    case "ReadTextBoundedOk": {
      const text = matched41.text;
      const owner: number | null = parseInt(text.trim(), 10);
      const self: number = hostCurrentPid();
      if (((owner == null) || (owner <= 1) || (owner === self) || !(hostAliveP(owner)))) {
        return 0;
      } else {
        const termStatus: number = hostSignal(owner, 15);
        const termWait: number = ((termStatus === 0) ? hostWaitNotAlive(owner, childStopTimeoutMs) : termStatus);
        if ((termWait === 0)) {
          return 0;
        } else {
          const killStatus: number = hostSignal(owner, 9);
          if ((killStatus !== 0)) {
            return killStatus;
          } else {
            return hostWaitNotAlive(owner, childStopTimeoutMs);
          }
        }
      }
    }
  }
}

function installOwnerPid(paths: ActivityPaths, descriptor: number): LeaseResult {
  const matched42 = hostWriteTextAtomic(paths.pid, (String(hostCurrentPid()) + String("\n")));
  switch (matched42.tag) {
    case "WriteTextAtomicOk": {
      return makeLeaseAcquired(descriptor);
    }
    case "WriteTextAtomicError": {
      const errno = matched42.errno;
      hostUnlock(descriptor);
      return makeLeaseRejected((String("cannot write owner pid: errno ") + String(errno)));
    }
  }
}

function acquireLease(paths: ActivityPaths, attempt: number): LeaseResult {
  const matched43 = hostLockExclusive(paths.lease);
  switch (matched43.tag) {
    case "LockExclusiveOk": {
      const descriptor = matched43.descriptor;
      return installOwnerPid(paths, descriptor);
    }
    case "LockExclusiveError": {
      const errno = matched43.errno;
      if ((attempt >= leaseAttemptLimit)) {
        return makeLeaseRejected((String("cannot acquire sole-writer lease: errno ") + String(errno)));
      } else {
        takeoverOwner(paths.pid);
        hostSleep(leaseRetryDelayMs);
        return acquireLease(paths, (attempt + 1));
      }
    }
  }
}

function ensureFifo(path: string): number {
  const matched44 = hostPathKind(path);
  switch (matched44.tag) {
    case "PathKindOk": {
      const kind = matched44.kind;
      if ((kind === 4)) {
        return 0;
      } else {
        return -22;
      }
    }
    case "PathKindError": {
      const errno = matched44.errno;
      if ((errno === 2)) {
        return hostFifoCreate(path);
      } else {
        return (0 - errno);
      }
    }
  }
}

function openControl(path: string): number {
  const fifoStatus: number = ensureFifo(path);
  if ((fifoStatus === 0)) {
    return hostFifoOpenRead(path);
  } else {
    return fifoStatus;
  }
}

function startEventStream(): EventStreamResult {
  const matched45 = hostSpawnStdout(["niri", "msg", "--json", "event-stream"]);
  switch (matched45.tag) {
    case "SpawnStdoutOk": {
      const pid = matched45.pid;
      const stdoutFd = matched45.stdoutFd;
      return makeEventStreamStarted(pid, stdoutFd);
    }
    case "SpawnStdoutError": {
      const errno = matched45.errno;
      return makeEventStreamRejected(errno);
    }
  }
}

function readDescriptorLine(descriptor: number): LineResult {
  const matched46 = hostReadLineDeadline(descriptor, maxLineBytes, pollTimeoutMs);
  switch (matched46.tag) {
    case "ReadLineOk": {
      const line = matched46.line;
      const eof = matched46.eof;
      return makeLineLoaded(line, eof);
    }
    case "ReadLineError": {
      const errno = matched46.errno;
      return makeLineRejected(errno);
    }
  }
}

function reapChild(pid: number, stdoutFd: number): number {
  const closeStatus: number = hostClose(stdoutFd);
  const firstWait: number = hostWaitNotAlive(pid, childStopTimeoutMs);
  const stopped: number = ((firstWait === 0) ? 0 : (() => {
    const termStatus: number = hostSignal(pid, 15);
    if ((termStatus !== 0)) {
      return termStatus;
    } else {
      const termWait: number = hostWaitNotAlive(pid, childStopTimeoutMs);
      if ((termWait === 0)) {
        return 0;
      } else {
        const killStatus: number = hostSignal(pid, 9);
        if ((killStatus !== 0)) {
          return killStatus;
        } else {
          return hostWaitNotAlive(pid, childStopTimeoutMs);
        }
      }
    }
  })());
  if ((stopped === 0)) {
    const waitStatus: number = hostWait(pid);
    if ((closeStatus === 0)) {
      return waitStatus;
    } else {
      return closeStatus;
    }
  } else {
    return stopped;
  }
}

function reconnectEventStream(pid: number, stdoutFd: number): EventStreamResult {
  reapChild(pid, stdoutFd);
  hostSleep(reconnectDelayMs);
  return startEventStream();
}

function reopenControl(path: string, descriptor: number): number {
  hostClose(descriptor);
  hostSleep(leaseRetryDelayMs);
  return hostFifoOpenRead(path);
}

function daemonLoop(paths: ActivityPaths, initialState: a.ActivityState, initialControlFd: number, initialEventPid: number, initialEventFd: number): number {
  let state: a.ActivityState = initialState;
  let controlFd: number = initialControlFd;
  let eventPid: number = initialEventPid;
  let eventFd: number = initialEventFd;
  loop47: while (true) {
    const ready: number = hostPollReadable([eventFd, controlFd], idlePollTimeoutMs);
    if ((ready === eventFd)) {
      const matched48 = readDescriptorLine(eventFd);
      switch (matched48.tag) {
        case "LineLoaded": {
          const line = matched48.line;
          const eof = matched48.eof;
          if (eof) {
            const matched49 = reconnectEventStream(eventPid, eventFd);
            switch (matched49.tag) {
              case "EventStreamRejected": {
                const errno = matched49.errno;
                stderrLine((String("activity daemon: cannot reconnect niri: errno ") + String(errno)));
                hostSleep(reconnectDelayMs);
                const matched50 = startEventStream();
                switch (matched50.tag) {
                  case "EventStreamRejected": {
                    const secondErrno = matched50.errno;
                    return secondErrno;
                  }
                  case "EventStreamStarted": {
                    const nextPid = matched50.pid;
                    const nextFd = matched50.stdoutFd;
                    [state, controlFd, eventPid, eventFd] = [state, controlFd, nextPid, nextFd];
                    continue loop47;
                  }
                }
              }
              case "EventStreamStarted": {
                const nextPid = matched49.pid;
                const nextFd = matched49.stdoutFd;
                [state, controlFd, eventPid, eventFd] = [state, controlFd, nextPid, nextFd];
                continue loop47;
              }
            }
          } else {
            [state, controlFd, eventPid, eventFd] = [handleEvent(paths, state, line), controlFd, eventPid, eventFd];
            continue loop47;
          }
        }
        case "LineRejected": {
          const errno = matched48.errno;
          const matched51 = reconnectEventStream(eventPid, eventFd);
          switch (matched51.tag) {
            case "EventStreamRejected": {
              const reconnectErrno = matched51.errno;
              return reconnectErrno;
            }
            case "EventStreamStarted": {
              const nextPid = matched51.pid;
              const nextFd = matched51.stdoutFd;
              [state, controlFd, eventPid, eventFd] = [state, controlFd, nextPid, nextFd];
              continue loop47;
            }
          }
        }
      }
    }
    if ((ready === controlFd)) {
      const matched52 = readDescriptorLine(controlFd);
      switch (matched52.tag) {
        case "LineLoaded": {
          const line = matched52.line;
          const eof = matched52.eof;
          if (eof) {
            const nextControl: number = reopenControl(paths.ctl, controlFd);
            if ((nextControl < 0)) {
              return nextControl;
            } else {
              [state, controlFd, eventPid, eventFd] = [state, nextControl, eventPid, eventFd];
              continue loop47;
            }
          } else {
            [state, controlFd, eventPid, eventFd] = [handleCommand(paths, state, line), controlFd, eventPid, eventFd];
            continue loop47;
          }
        }
        case "LineRejected": {
          const errno = matched52.errno;
          const nextControl: number = reopenControl(paths.ctl, controlFd);
          if ((nextControl < 0)) {
            return nextControl;
          } else {
            [state, controlFd, eventPid, eventFd] = [state, nextControl, eventPid, eventFd];
            continue loop47;
          }
        }
      }
    }
    if ((ready === pollTimeoutStatus)) {
      [state, controlFd, eventPid, eventFd] = [state, controlFd, eventPid, eventFd];
      continue loop47;
    }
    if (true) {
      return ready;
    }
  }
}

function initialState(defs: a.ActivityDef[], defaultActivity: string, assignments: a.Assignment[]): a.ActivityState {
  return a.makeActivityState(defs, defaultActivity, assignments, [], [], defaultActivity, defaultActivity, []);
}

function runOwnedDaemon(paths: ActivityPaths, leaseDescriptor: number, defs: a.ActivityDef[], defaultActivity: string, assignments: a.Assignment[]): number {
  const controlFd: number = openControl(paths.ctl);
  if ((controlFd < 0)) {
    hostUnlock(leaseDescriptor);
    stderrLine((String("activity daemon: cannot open control FIFO: errno ") + String((0 - controlFd))));
    return 1;
  } else {
    const state: a.ActivityState = rescanState(paths, initialState(defs, defaultActivity, assignments));
    const matched53 = startEventStream();
    switch (matched53.tag) {
      case "EventStreamRejected": {
        const errno = matched53.errno;
        hostClose(controlFd);
        hostUnlock(leaseDescriptor);
        stderrLine((String("activity daemon: cannot start niri event stream: errno ") + String(errno)));
        return 1;
      }
      case "EventStreamStarted": {
        const pid = matched53.pid;
        const stdoutFd = matched53.stdoutFd;
        const status: number = daemonLoop(paths, state, controlFd, pid, stdoutFd);
        reapChild(pid, stdoutFd);
        hostClose(controlFd);
        hostUnlock(leaseDescriptor);
        if ((status === 0)) {
          return 0;
        } else {
          return 1;
        }
      }
    }
  }
}

function runDaemon(defsOverride: string | null): number {
  const paths: ActivityPaths = activityPaths(defsOverride);
  if (((makeParent(paths.ctl) !== 0) || (makeParent(paths.state) !== 0))) {
    stderrLine("activity daemon: cannot create runtime directories");
    return 1;
  } else {
    const matched54 = loadDefs(paths.defs);
    switch (matched54.tag) {
      case "DefsRejected": {
        const message = matched54.message;
        stderrLine((String("activity daemon: ") + String(message)));
        return 1;
      }
      case "DefsLoaded": {
        const defs = matched54.defs;
        const defaultActivity = matched54.defaultActivity;
        const matched55 = loadAssignments(paths.assignments);
        switch (matched55.tag) {
          case "AssignmentsRejected": {
            const message = matched55.message;
            stderrLine((String("activity daemon: ") + String(message)));
            return 1;
          }
          case "AssignmentsLoaded": {
            const assignments = matched55.assignments;
            const matched56 = acquireLease(paths, 0);
            switch (matched56.tag) {
              case "LeaseRejected": {
                const message = matched56.message;
                stderrLine((String("activity daemon: ") + String(message)));
                return 1;
              }
              case "LeaseAcquired": {
                const descriptor = matched56.descriptor;
                stdoutLine((String("activity daemon up: defs=") + String(paths.defs) + String(" activities=") + String(defs.length)));
                return runOwnedDaemon(paths, descriptor, defs, defaultActivity, assignments);
              }
            }
          }
        }
      }
    }
  }
}

function snapshotListEntry(events: json.JsonEvent[], start: number): ListEntry | null {
  const id: string | null = jsonStringAt(events, jsonObjectFieldIndex(events, start, "id"));
  const workspacesIndex: number | null = jsonObjectFieldIndex(events, start, "workspaces");
  if (((id == null) || (workspacesIndex == null) || !((events[workspacesIndex].tag === "JsonArrayStart")))) {
    return null;
  } else {
    const end: number = jsonValueEnd(events, workspacesIndex);
    if ((end < 0)) {
      return null;
    } else {
      let index: number = (workspacesIndex + 1);
      let items: number = 0;
      loop57: while (true) {
        if ((index === (end - 1))) {
          return makeListEntry(id, items);
        } else {
          const next: number = jsonValueEnd(events, index);
          if ((next < 0)) {
            return null;
          } else {
            [index, items] = [next, (items + 1)];
            continue loop57;
          }
        }
      }
    }
  }
}

function snapshotListEntries(events: json.JsonEvent[], start: number): ListEntry[] | null {
  if (((start < 0) || (start >= events.length) || !((events[start].tag === "JsonArrayStart")))) {
    return null;
  } else {
    const end: number = jsonValueEnd(events, start);
    const emptyEntries: ListEntry[] = [];
    if ((end < 0)) {
      return null;
    } else {
      let index: number = (start + 1);
      let result: ListEntry[] = emptyEntries;
      loop58: while (true) {
        if ((index === (end - 1))) {
          return result;
        } else {
          const entry: ListEntry | null = snapshotListEntry(events, index);
          const next: number = jsonValueEnd(events, index);
          if (((entry == null) || (next < 0))) {
            return null;
          } else {
            [index, result] = [next, [...result, entry]];
            continue loop58;
          }
        }
      }
    }
  }
}

function parseSnapshot(text: string): SnapshotResult {
  const matched59 = json.decode(text);
  switch (matched59.tag) {
    case "JsonDecodeError": {
      const offset = matched59.offset;
      const message = matched59.message;
      return makeSnapshotMissing(true);
    }
    case "JsonDecoded": {
      const events = matched59.events;
      if ((events.length === 0 || !(((events[0] ?? null).tag === "JsonObjectStart")))) {
        return makeSnapshotMissing(true);
      } else {
        const current: string | null = jsonStringAt(events, jsonObjectFieldIndex(events, 0, "current"));
        const entriesIndex: number | null = jsonObjectFieldIndex(events, 0, "activities");
        const entries: ListEntry[] | null = ((entriesIndex == null) ? null : snapshotListEntries(events, entriesIndex));
        if (((current == null) || (entries == null))) {
          return makeSnapshotMissing(true);
        } else {
          return makeSnapshotLoaded(makeSnapshotView(text, current, entries));
        }
      }
    }
  }
}

function readSnapshot(path: string): SnapshotResult {
  const matched60 = hostReadTextBounded(path, maxStateBytes);
  switch (matched60.tag) {
    case "ReadTextBoundedOk": {
      const text = matched60.text;
      return parseSnapshot(text);
    }
    case "ReadTextBoundedError": {
      const errno = matched60.errno;
      return makeSnapshotMissing(true);
    }
  }
}

function commandJsonEvents(command: string, activity: string | null, ordinal: number | null): json.JsonEvent[] {
  const events: json.JsonEvent[] = [];
  const base: json.JsonEvent[] = [...events, ({ tag: "JsonObjectStart", offset: 0 } as json.JsonEvent), ({ tag: "JsonKey", offset: 0, value: "cmd" } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: command } as json.JsonEvent)];
  const withActivity: json.JsonEvent[] = ((activity == null) ? base : [...base, ({ tag: "JsonKey", offset: 0, value: "activity" } as json.JsonEvent), ({ tag: "JsonString", offset: 0, value: activity } as json.JsonEvent)]);
  const withOrdinal: json.JsonEvent[] = ((ordinal == null) ? withActivity : [...withActivity, ({ tag: "JsonKey", offset: 0, value: "n" } as json.JsonEvent), ({ tag: "JsonNumber", offset: 0, lexeme: (String(ordinal)) } as json.JsonEvent)]);
  return [...withOrdinal, ({ tag: "JsonObjectEnd", offset: 0 } as json.JsonEvent)];
}

function sendCommand(paths: ActivityPaths, command: string, activity: string | null, ordinal: number | null): number {
  const matched61 = json.encode(commandJsonEvents(command, activity, ordinal));
  switch (matched61.tag) {
    case "JsonEncodeError": {
      const eventIndex = matched61.eventIndex;
      const message = matched61.message;
      stdoutLine("activity: cannot encode command");
      return 1;
    }
    case "JsonEncoded": {
      const text = matched61.text;
      const status: number = hostFifoWriteDeadline(paths.ctl, (String(text) + String("\n")), fifoWriteTimeoutMs);
      if ((status === 0)) {
        return 0;
      } else {
        stdoutLine("activity: daemon not reachable (systemctl --user status activity-daemon)");
        return 1;
      }
    }
  }
}

function printList(snapshot: SnapshotView, flag: string | null): number {
  if ((flag === "--json")) {
    stdoutLine(snapshot.text.trim());
    return 0;
  }
  if ((flag === "--menu")) {
    const entries: ListEntry[] = snapshot.entries;
    let index: number = 0;
    loop62: while (true) {
      if ((index >= entries.length)) {
        return 0;
      } else {
        stdoutLine(entries[index].id);
        [index] = [(index + 1)];
        continue loop62;
      }
    }
  }
  if (true) {
    const entries: ListEntry[] = snapshot.entries;
    let index: number = 0;
    loop63: while (true) {
      if ((index >= entries.length)) {
        return 0;
      } else {
        const entry: ListEntry = entries[index];
        stdoutLine((String(((entry.id === snapshot.current) ? "* " : "  ")) + String(entry.id) + String("  (") + String(entry.workspaceCount) + String(")")));
        [index] = [(index + 1)];
        continue loop63;
      }
    }
  }
}

function listCommand(paths: ActivityPaths, flag: string | null): number {
  const matched64 = readSnapshot(paths.state);
  switch (matched64.tag) {
    case "SnapshotMissing": {
      const token = matched64.token;
      stdoutLine("activity: no state yet (daemon not running?)");
      return 1;
    }
    case "SnapshotLoaded": {
      const snapshot = matched64.snapshot;
      return printList(snapshot, flag);
    }
  }
}

function currentCommand(paths: ActivityPaths): number {
  const matched65 = readSnapshot(paths.state);
  switch (matched65.tag) {
    case "SnapshotMissing": {
      const token = matched65.token;
      stdoutLine("activity: no state yet");
      return 1;
    }
    case "SnapshotLoaded": {
      const snapshot = matched65.snapshot;
      stdoutLine(snapshot.current);
      return 0;
    }
  }
}

function parsedOrdinal(value: string | null): number {
  if ((value == null)) {
    return 1;
  } else {
    const parsed: number | null = parseInt(value, 10);
    if ((parsed == null)) {
      return 1;
    } else {
      return parsed;
    }
  }
}

function usage(): number {
  stdoutLine((String("usage: activity daemon [--defs PATH] | goto ACTIVITY | back | here N | ") + String("move-here N | move-to-activity ACTIVITY | assign ACTIVITY | ") + String("list [--menu|--json] | current")));
  return 0;
}

export function run(args: string[]): number {
  if (args.length === 0) {
    return usage();
  } else {
    const command: string = args[0];
    const second: string | null = ((1 < args.length) ? args[1] : null);
    const third: string | null = ((2 < args.length) ? args[2] : null);
    const paths: ActivityPaths = activityPaths(null);
    if ((command === "daemon")) {
      return runDaemon(((second === "--defs") ? third : null));
    }
    if ((command === "goto")) {
      if ((second == null)) {
        return usage();
      } else {
        return sendCommand(paths, "goto", second, null);
      }
    }
    if ((command === "move-to-activity")) {
      if ((second == null)) {
        return usage();
      } else {
        return sendCommand(paths, "move-to-activity", second, null);
      }
    }
    if ((command === "back")) {
      return sendCommand(paths, "back", null, null);
    }
    if ((command === "here")) {
      const ordinal: number = parsedOrdinal(second);
      return sendCommand(paths, "here", null, ordinal);
    }
    if ((command === "move-here")) {
      const ordinal: number = parsedOrdinal(second);
      return sendCommand(paths, "move-here", null, ordinal);
    }
    if ((command === "assign")) {
      if ((second == null)) {
        return usage();
      } else {
        return sendCommand(paths, "assign", second, null);
      }
    }
    if ((command === "list")) {
      return listCommand(paths, second);
    }
    if ((command === "current")) {
      return currentCommand(paths);
    }
    if (true) {
      return usage();
    }
  }
}
