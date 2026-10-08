---
name: codex-lead
description: >-
  Run work through a Codex lead session that Claude supervises: start it, give it a goal, message it, watch its worker tree and keep it on a tight leash. Use when Tom asks to drive work through Codex, or for a Codex lead or orchestrator.
---

# Supervise a Codex lead

Claude writes the brief, starts one Codex lead session, then supervises it
from outside with the `codex-lead` command. Nothing here types into a window
or takes Tom's focus.

## Steps

1. Write the brief from the template below to
   `~/.local/state/agents/handoffs/codex-lead-brief.md`.
2. `codex-lead start ~/.local/state/agents/handoffs/codex-lead-brief.md`
   opens the lead in a window that doesn't take focus (the bar marks it
   urgent), sends "read BRIEF and follow it" as its first message, and prints
   the thread id. It saves the id, so later calls need no argument. To
   supervise an existing lead, set `CODEX_LEAD_THREAD=<id>`; `codex-lead id`
   prints the newest session Tom or Claude started (not a worker).
   Extra arguments go to `codex`, such as `-m gpt-6-astra`.
3. `codex-lead goal "Drive every item in <brief> (Order 1-N) until each is
   closed on GitHub or has a named blocker with evidence and an owner"`.
4. Run the supervision loop until the queue is empty, then tell Tom.

## Commands

- `codex-lead send "MSG"`: delivers at once. It steers the message into the
  lead's running turn, or starts a turn if the lead is idle, and prints which.
- `codex-lead goal "TEXT"` / `codex-lead goal-get`: replace or print the goal.
- `codex-lead status [N]`: the status file, then the lead's last N steps.
- `codex-lead workers`: the worker tree with path, model, effort, tokens and
  minutes since each last moved.

## Brief template

```markdown
# Codex lead brief
Role: you are the Codex lead for <scope>. You staff workers, land their
work and keep the status file current. You don't do the work yourself.
Read first: ~/.codex/AGENTS.md, <repo>/AGENTS.md, <issues or notes>.
Staffing: one worker per independent issue, all independent items at once.
  SOL 6.1 (gpt-6.1-sol) medium for ordinary and simple work (never low),
  high for hard implementation; Astra (gpt-6-astra) xhigh for hard
  reasoning, max for the hardest problems or a stuck fix loop. A box a
  worker failed starts one tier up.
Every worker brief: goal, files, Done when, ETA, and the lines
  Item: <repo#N>
  Category: <category from AGENTS.md>
  Follows: <agent id>   (only when it continues earlier work)
GitHub budget: 20 concurrent Actions jobs and 5,000 API calls an hour,
  shared with every other agent. Poll with backoff; no wide matrices.
Waiting: wait on farm runs and CI with one blocking command (`--wait`, or
  `gh run watch RUN --exit-status`), never a polling loop. Confirm the exact
  revision before dispatching a farm run.
Queue, in order (start every item that doesn't depend on another now):
  1. <repo#N> <one line> - Done when: <check>
  2. ...
Status file: keep ~/.local/state/agents/handoffs/codex-lead-status.md
  current after every landing, failure or staffing change, in this shape:
    Updated: <time>
    Running: <item> <worker path> <model/effort> <ETA>
    Closed: <item> <outcome with numbers>
    Blocked: <item> <blocker, evidence, owner>
    Next: <what starts next>
    Needs Tom: <nothing, or the one decision>
```

## Supervision loop

Check at most every 20 minutes. Each check:

- `codex-lead status` and `codex-lead workers`.
- Idle or overrunning workers: idle 20+ minutes, or past twice their ETA.
  Tell the lead to get a report, hand off, or restaff one tier up.
- Starting tiers: does each worker's model and effort fit the work and its
  history (`worker-ledger --summary`)? Say which to change.
- Parallel work: are independent queue items running at the same time?
  If the lead queued them behind one item, tell it to start them now.
- Closures since the last check:
  `gh issue list -R tompassarelli/<repo> --state closed --search 'closed:>=<ISO time>'`.
- Worker briefs carry the Item and Category lines: `threads list` should show
  each running item held. Ask the lead to fix any that don't.

Send corrections in one message per check with `codex-lead send`. Refresh the
goal hourly, or right away when the queue changes.

## Known failure modes

- The daemon socket moves when the daemon restarts, and
  `~/code/north-data/codex-pooled/app-server-control/app-server-control.sock`
  can point at a dead one. The command finds the listening socket under
  `/tmp/codex-daemon-1000/` on every call.
- Never use `codex queue`: it holds the message until the lead's turn ends,
  and a lead on a goal can stay in one turn for hours. On 8 Oct seven
  messages sat unread for 20 minutes that way.
- A Codex TUI makes its thread only on its first message, so the lead starts
  with the prompt as an argument. Never type into its window.
- `send` reaches a thread only while a session runs it. A finished
  `codex exec` thread accepts the message but never answers.
- Worker messages in the lead's log are encrypted; read a worker's brief by
  asking the lead, not from the log.
- Thread data: `~/code/north-data/codex-pooled/sqlite/state_5.sqlite`
  (tables `threads`, `thread_spawn_edges`); logs under
  `~/code/north-data/codex-pooled/sessions/YYYY/MM/DD/`.
- Clean up test threads with `codex archive --remote unix://<socket> <id>`.
