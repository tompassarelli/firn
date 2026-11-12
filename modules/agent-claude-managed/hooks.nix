runtime:
let
  command =
    kind:
    "${runtime}/env -u BASH_ENV -u ENV PATH=${runtime}:/run/current-system/sw/bin north hook ${kind}";
  hook = kind: {
    type = "command";
    command = command kind;
    timeout = 60;
  };
  entry = kinds: {
    hooks = map hook kinds;
  };
  matched = matcher: kinds: {
    inherit matcher;
    hooks = map hook kinds;
  };
in
{
  PermissionRequest = [ (matched "Bash" [ "dispatch" ]) ];
  PostToolUse = [ (entry [ "dispatch" ]) ];
  PreToolUse = [
    (matched "Write|Edit|MultiEdit|NotebookEdit|Bash" [ "language-guard" ])
    (matched "Edit|Write|MultiEdit" [ "firn-system-policy" ])
    (matched "Bash" [
      "firn-system-policy"
      "dispatch"
    ])
    (matched "Agent" [ "dispatch" ])
    (matched "CronCreate|ScheduleWakeup" [ "dispatch" ])
    (matched "Edit|Write|MultiEdit|NotebookEdit" [ "dispatch" ])
    (matched "SendMessage" [ "dispatch" ])
    (matched "AskUserQuestion" [ "dispatch" ])
  ];
  SessionStart = [ (entry [ "dispatch" ]) ];
  Stop = [ (entry [ "dispatch" ]) ];
  SubagentStop = [ (entry [ "dispatch" ]) ];
  UserPromptSubmit = [
    (entry [ "prompt-grounding" ])
    (entry [ "dispatch" ])
  ];
}
