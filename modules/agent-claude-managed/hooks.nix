runtime:
let
  env = "${runtime}/env";
  run =
    kind: "${env} -u BASH_ENV -u ENV PATH=${runtime}:/run/current-system/sw/bin north hook ${kind}";
  failClosed = kind: "test -x ${env} || exit 2; ${run kind}";
  hook = command: {
    type = "command";
    inherit command;
    timeout = 60;
  };
  entry = kinds: {
    hooks = map (kind: hook (run kind)) kinds;
  };
  gated = matcher: kinds: {
    inherit matcher;
    hooks = map (kind: hook (failClosed kind)) kinds;
  };
in
{
  PermissionRequest = [ (gated "Bash" [ "dispatch" ]) ];
  PostToolUse = [ (entry [ "dispatch" ]) ];
  PreToolUse = [
    (gated "Write|Edit|MultiEdit|NotebookEdit|Bash" [ "language-guard" ])
    (gated "Edit|Write|MultiEdit" [ "firn-system-policy" ])
    (gated "Bash" [
      "firn-system-policy"
      "dispatch"
    ])
    (gated "Agent" [ "dispatch" ])
    (gated "CronCreate|ScheduleWakeup" [ "dispatch" ])
    (gated "Edit|Write|MultiEdit|NotebookEdit" [ "dispatch" ])
    (gated "SendMessage" [ "dispatch" ])
    (gated "AskUserQuestion" [ "dispatch" ])
  ];
  SessionStart = [ (entry [ "dispatch" ]) ];
  Stop = [ (entry [ "dispatch" ]) ];
  SubagentStop = [ (entry [ "dispatch" ]) ];
  UserPromptSubmit = [
    (entry [ "prompt-grounding" ])
    (entry [ "dispatch" ])
  ];
}
