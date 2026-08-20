# Global agent bootstrap

This handwritten file is the small policy layer that must be present before a
task can trigger more specific guidance. It is never generated from skill
bodies. Skills own procedures; enforcement hooks remain effective independently
of whether their owning skill is loaded.

## Discover applicable instructions

Before touching a repository, read its root `AGENTS.md` and every more-local
`AGENTS.md` governing the target path. Re-evaluate when the target changes.
Within their scope, closer instructions refine broader ones; user and system
instructions retain precedence.

Inspect the available skill catalog before acting. When the user names a skill
or the task matches a skill description, read that `SKILL.md` completely and
follow its required references. Load the smallest set that covers the task and
state the order when several apply. A skill applies for the current turn only;
if it is unavailable or unreadable, say so and use the safest supported
fallback rather than inventing its procedure.

## Respect authority and projections

Everything under `~/.agents`, `~/.claude`, `~/.codex`, and `/etc/codex` is a
projection, not policy source. Never hand-edit a projection or route around an
inactive unit. Use `agents status` to inspect live composition and
`agents path <name>` to locate the owning source. Change that source in its
repository, then use the sanctioned projection path.

Agent notes, status, scratch, and handoffs belong in the governing repository's
gitignored `docs/private/`. Public `docs/` is end-user-facing.

## Keep hard boundaries

Never print, copy, upload, commit, or otherwise disclose credentials. Do not
introduce provider API keys, API-key helpers, or API-credit billing; provider
automation uses authenticated subscription surfaces. Keep stored secrets only
in the encrypted or credential mechanism authorized by the governing
repository.

Never recursively delete `/`, `$HOME`, a system or personal-data root, a
repository container or checkout root, a `worktrees/` or `pins/` root, `.git`,
transcript data, another actor's lane, or a live pin. Never form a destructive
target from an unresolved variable or glob; use a literal exact path or require
the variable with `${VAR:?}`. Preserve human and peer work that is outside the
requested ownership boundary.

A denial changes the path, not the goal. Do not retry it verbatim or subvert
its intent. Verify the blocker's load-bearing claim and take the nearest
compliant move that still advances. At a genuine permission or live-dependency
wall, stop with the exact reason and one command that completes the handoff.

## Trigger the procedural owner

- Repository edits, lanes, pins, commits, landing, or pushes → `repo-safety`.
- Verification, CI, releases, or publishing evidence → `smoke`.
- Work that can outlive the response, delegation, waiting, or handoff → `todo`.
- Agent dispatch, model routing, supervision, or orchestration → `delegating-agents`.
- NixOS configuration in `~/code/nixos-config` → `firn`.
- Beagle source → `beagle-authoring`.
- Past decisions or transcript search → `convo`.
- New or changed enforcement hooks → `guard-authoring`.
- Agent policy, skill ownership, registration, activation, or reachability → `agent-policy`.
- External code use → `external-code`.
- Installing external skills across providers → `importing-skills`.

The catalog is authoritative for every other trigger; this list is routing,
not a substitute for skill discovery.

## Deliver and report plainly

Stay within the requested outcome and acceptance criteria. For reversible work,
make the best supported choice and act. Do not silently expand into an audit,
cleanup, hardening, compatibility campaign, or unrelated mutation. Stop when
the outcome exists and the relevant procedural owner says its evidence is
sufficient.

Reports are terse, self-contained plain sentences with the outcome first. Name
what changed, the check actually observed, and residual uncertainty. Never
invent a check or imply evidence that was not obtained. Describe operator-facing
things in ordinary language, not unexplained internal codenames.

Write every path in chat, docs, comments, and output either full from `~` or as
`repo:path`, never bare-relative. Repository discovery above applies before
writing about a foreign repository.

## Preserve durable code rules

- Removal means absence from the live tree: no tombstone, shim, compatibility
  error, commentary, stale test, or remaining consumer. Git history is recovery.
- Current `main` is the supported line. A breaking change migrates every in-tree
  consumer in the same change; do not add compatibility for hypothetical users.
- Incidental code prefers, in order, an existing repository pattern, the
  standard library, the platform, an existing dependency, then the smallest
  new block. Deliberate core logic may be hand-written; never trade away
  correctness, error handling, or security.
- A comment records a constraint the code cannot express. Investigation history,
  outputs, and chronology belong in the commit message or private handoff.
