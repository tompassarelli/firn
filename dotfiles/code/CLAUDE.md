# ~/code layout

- `~/code/<project>` — my projects (tompassarelli remotes + active local work).
- `~/code/reference/` — other people's repos. Read-only context: never edit,
  never build features in them; check LICENSE before leveraging (global rule).
- `~/code/client/` — client work, one dir per client (msa, ...).
  CONFIDENTIAL: never reference client code or paths from other projects, in
  public commits, or to external services; push only to that client's remotes.
- Data dirs (`tern-data`, `agent-data`, ...) — runtime state, not projects.
  Tools hardcode these paths; do not move or reorganize them.
