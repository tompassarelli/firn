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
self-contained; the cloud worker has none of your local context. Its commits
say `Refs <repo>#N` for the issue. Don't let it send push notifications. End
every cloud prompt with: "push to claude/<name>; it lands itself if it
passes".

## Landing

Nobody relays it. In smashcraft and wisp, a push to `claude/**` starts the
repo's Autoland workflow (`.github/workflows/autoland.yml`; each repo's
docs/ci.md, "Autoland"): rebase onto main, the repo's checks, the full farm
suite on GitHub's runners, then a comparison with main's own failures. No new
failures: it lands on main, deletes the branch and starts main's CI. A
conflict, failed check or new failing test leaves the branch and comments on
the `Refs` issue with the files or tests; push a fix to the same branch.
Branches land one at a time in push order.

Retry a branch without a new commit:
`gh workflow run autoland.yml -R tompassarelli/<repo> -f branch=claude/<name>`.
A commit that changes `.github/workflows/` can't land this way (the workflow
token can't push workflow files); land it locally with `safe-push`.
