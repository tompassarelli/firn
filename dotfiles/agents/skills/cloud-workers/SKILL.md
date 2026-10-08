---
name: cloud-workers
description: >-
  Run code-only worker tasks in Anthropic's cloud through Claude Code routines
  with the RemoteTrigger tool: when local CPU is busy or the task needs no
  local files, Warcraft or private inputs.
---

# Cloud workers

## What fits

- Code-only work in public GitHub repos (`tompassarelli/wisp`,
  `tompassarelli/smashcraft`) that needs no local files, private build inputs,
  Warcraft clients or Tom's install.
- Sandbox: 4 cores, 15 GB, Bun 1.4.2, gcc and clang. No Lua: build Lua 5.3.6
  with `LUA_32BITS`, or use Wisp's pinned Lua command once wisp#64 lands.
- Cost: plan usage, like a local worker; no separate compute charge. Extra
  usage is off on Tom's account, so hitting the limit pauses work instead of
  billing. Up to 100 runs an hour per account.

## Run a job

Only the main session has RemoteTrigger; workers don't.

Reuse one routine per repo. Routines can't be deleted by API, only at
claude.ai/code/routines, so never make one per job. Existing routine:
`wisp-cloud-worker`, id `trig_01Rv4YsBNXztmR2bKGs4bsth`, environment Default
(`env_01EkrXafT5PjQN9jUWzwMhLd`).

To create a routine for another repo, use this body:

```json
{"name": "<repo>-cloud-worker", "run_once_at": "<far future>", "enabled": true,
 "job_config": {"ccr": {
   "environment_id": "env_01EkrXafT5PjQN9jUWzwMhLd",
   "session_context": {"model": "claude-opus-5-5",
     "sources": [{"git_repository": {"url": "https://github.com/tompassarelli/<repo>"}}],
     "allowed_tools": ["..."]},
   "events": [{"data": {"uuid": "<fresh v4>", "session_id": "", "type": "user",
     "parent_tool_use_id": null,
     "message": {"role": "user", "content": "<PROMPT>"}}}]}}}
```

For each job:

1. `update` the routine: replace `events[0]`'s message content with the brief
   and give it a fresh v4 uuid.
2. `run` it. The response gives the session id.
3. Read results with `get_run_log` (session id) or `list_runs`. A run took
   about 30 s for install plus check.

## Briefs

Same four parts as a local worker: goal, files, Done when, ETA. Make it
self-contained; the cloud worker has none of your local context. Tell it to
push to a `claude/<slug>` branch, never main, and not to send push
notifications.

## Landing

The orchestrator (or a local worker) fetches the branch, cherry-picks it onto
current main in a worktree, runs the repo's checks and lands with
`safe-push`.
