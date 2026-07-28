# ~/code layout

- `~/code/<project>` — my projects (tompassarelli remotes + active local work).
- `~/code/reference/` — other people's repos. Read-only context: never edit,
  never build features in them; check LICENSE before leveraging (global rule).
- respect licenses when copying/inspired by code form reference
- `~/code/client/` — client work, one dir per client (msa, ...).
  CONFIDENTIAL: never reference client code or paths from other projects, in
  public commits, or to external services; push only to that client's remotes.
- Data dirs (`north-data`, `agent-data`, ...) — runtime state, not projects.
  Tools hardcode these paths; do not move or reorganize them.

## Worktrees

Durable personal worktrees live under a project-scoped root:
`~/code/worktrees/<project>/<slug>` (e.g. `~/code/worktrees/north/policy-graph`).

- **Primary checkouts are unchanged** — `~/code/<project>` stays the main
  working copy; only extra worktrees move under `~/code/worktrees/`.
- **Don't repeat `<project>` or `-wt-` in the leaf.** The project dir already
  names the project; the slug is just the branch/topic (`policy-graph`, not
  `north-wt-policy-graph` or `north/north-policy-graph`).
- **Billable-client worktrees stay guarded under their owner namespace**, with a
  `worktrees/<project>/<slug>` suffix inside it:
  `~/code/client/<owner>/worktrees/<project>/<slug>`. The client-confidentiality
  and clock guards still apply — they never move out to the shared root.
- **Reference repos get no worktrees** — `~/code/reference/` is read-only
  context; check out nothing extra there.
- **Ephemeral / system-owned worktrees keep their tool-owned locations** — those
  a tool creates and manages (temp build trees, harness scratch) stay wherever
  the tool puts them; this policy governs only durable human/agent worktrees.

## Launch-critical repos — agents never edit the primary

`~/code/fram`, `~/code/north`, and `~/code/beagle` are **launch-critical**: a
running daemon or a rebuild reads them, so a half-finished edit in the primary
checkout is not a private work-in-progress, it is a broken engine for everyone.

**An agent editing any of these three works in a worktree, never in
`~/code/<project>` itself.** Use `EnterWorktree`, or
`git -C ~/code/<project> worktree add ~/code/worktrees/<project>/<slug>`.
The human's own primary checkout is unaffected by this rule.

The two repos fail differently, and both failures are real:

- **fram — hard deadlock.** `north up` refuses to launch on a tracked-dirty Fram
  checkout, on purpose: a coordinator serving a half-edited engine is worse than
  one that refuses. Observed 2026-07-29 — an agent left ten modified files in
  `~/code/fram`, so the coordinator could not be restarted, so a rebuilt closure
  could not be adopted, so a measured 200x performance fix sat built-but-unused
  while every `firn rebuild` reported failure *after the build had already
  succeeded*. One dirty primary stalled the whole machine.
- **north / beagle / nixos-config — silent exclusion.** `firn rebuild` builds a
  COMMIT SNAPSHOT, so uncommitted work is simply not in the generation. Nothing
  errors; the change just doesn't take, which reads as "the fix didn't work"
  and sends the next agent debugging code that never shipped.

The general rule the three repos are instances of: **if something launches from
a checkout, that checkout is production.** Edit production in a worktree and
land through a ref, the same as you would a deploy.

