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

