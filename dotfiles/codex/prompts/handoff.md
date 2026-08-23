---
description: Stop cleanly and leave the work resumable from zero — thread-first
argument-hint: "[recipient handle]   (omit = park it back on the queue)"
---

# /handoff — thin North adapter

Executes north:docs/operating-manual.md §"Handoff — an explicit procedure".
The thread is the handoff; a repo-root dump is not.

1. **Stop at the nearest safe point.** Finish the current atomic operation only
   if it is bounded and safe; otherwise stop now and record the broken state
   exactly. No new scope. No cleanup that only improves appearances.
2. **Bind the thread:** `$AGENT_THREAD`, else the id this session already named,
   else `north capture "<title>"`.
3. **Write the delta** — `north tell <id> <pred> "<value>"`, one item per fact;
   never re-summarize what the thread already holds:
   - `progress` — `STOPPED: <what is true now> · NEXT: <exact first command>`
   - `progress` — where the work physically is: lane path under
     `<container>/worktrees/`, branch, anything unpushed or stashed. Dirty in a
     `main/`? `wt-rescue` first, then name the rescue lane it created at
     `<container>/worktrees/rescue-<ts>`. Never a diff in prose.
   - `learning` — each decision, rejected approach, constraint, misleading path
   - `done_when` — any completion bar the thread is still missing
   - `outcome` — only if the work is actually terminal
   Probes you ran: `north evidence record "<exact bar>" "<observed result>"`
   (prefix `--thread <id>` when `NORTH_RUN_ID` is unset).
4. **Offer it, or park it.** Recipient given: `north mention <handle> --about <id>
   "<one line>"`. None: `north retract <id> driver @<you>`, and it returns to
   `north ready`. Never set `driver` for someone else — only their own claim
   completes a handoff.
5. **A file only for a successor with no North:** `ensure-private-docs`, then
   `north show <id> > docs/private/handoff-<id>.md`. Never repo root. Coordinator
   down: write the frame there now — the thread write is still owed.

Reply one line: `handoff-ready @<id> — stopped at: <one sentence> · resume: north show <id>`
(recipient named: append ` → <handle>`).
