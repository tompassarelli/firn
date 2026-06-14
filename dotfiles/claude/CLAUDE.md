# Personal CLAUDE.md (global)

These rules apply to every session, regardless of working directory.

# life-os

When starting work on anything nontrivial, read
`./threads/CLAUDE.md` first. It's the operating manual for plans,
time tracking, and session behavior. If anything elsewhere in this
tree contradicts it, the threads manual wins.

Trivial actions — one-shell-command lookups, reading a single file,
quick clarifications — don't need the full manual loaded.

**Thread default state is `ready`** (not `draft`). When creating a
new thread, fresh captures go to `ready` — meaning "accepted;
executable; not yet in motion." Use `state: draft` explicitly only
for speculative captures that need triage before commitment. Full
rules in `~/code/life-os/threads/CLAUDE.md` (States section). 


## life-os is claim-backed — write safely under concurrent agents

life-os threads are backed by the Chelonia claim graph (engine `~/code/chelonia`;
canonical log `~/code/life-os/chelonia-data/claims.log`). Assume **other agents
may be editing concurrently**:

- Creating/editing a thread `.md` is fine — distinct files don't collide. After
  editing, run `~/code/life-os/bin/chelonia import` to fold edits into the claim
  log (idempotent; safe to run anytime).
- **Do not run `chelonia export` during concurrent work** — it regenerates
  `threads/` from the log and would clobber another agent's un-imported edits.
  (The engine refuses if files diverge, but don't rely on it.)
- **Serialized claim writes go through the coordinator** via `chelonia tell <id>
  <pred> <value>` / `untell <id> <pred> <value>` — these route to the running
  daemon (serialized, rule-checked, retries on conflict). Do NOT use `chelonia
  set`, which appends the log directly and races. For creating whole new threads,
  file-edit + `import` is fine (distinct files don't collide); for field changes
  on existing threads under concurrency, prefer `tell`.
- Reads are instant off the warm daemon (`chelonia serve`): ready / blocked /
  leverage / validate in ~1ms.


## When editing/advising, you need to resolve the CLAUDE.md files relevant to the work

Let's see the user alludes to something inside

```bash
ls ~/code/<repo>/..
```
Always start by identifying the claude.md at the root, which provides essential context

## Nix dev environments: use direnv, never recommend `nix develop` or `nix shell`

When a project has a Nix dev shell, the user activates it via **direnv**
(`.envrc` with `use flake` and a populated `.direnv/`). `cd <repo>`
auto-activates the shell; no manual command is needed.

Do not tell the user to run `nix develop` / `nix-shell`. If they're in
the project dir, the shell is already active. If `.envrc` is missing,
suggest writing one (`echo 'use flake' > .envrc && direnv allow`)
instead of recommending the bare `nix develop` workflow.

Same rule for `devenv` / `flake.nix devShells` — surface the direnv
trigger, not the underlying command.

## GitHub releases: version only in title

Use just the version tag as the release title (e.g. `v0.5.0`). No
`—` subtitle or description in the title. Details go in the body.
