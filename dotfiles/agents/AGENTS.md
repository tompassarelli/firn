# Global agent bootstrap

This is the always-loaded discovery and boundary layer. Procedures belong to
skills; enforcement hooks remain effective whether their owning skill is loaded.

## Discover applicable instructions

Before touching a repository, read its root and more-local `AGENTS.md` files.
Re-evaluate when the target changes. Closer instructions refine broader ones;
user and system instructions retain precedence.

Inspect the available skill catalog before acting. When the user names a skill
or the task matches its description, read that `SKILL.md` completely and follow
its required references. Load the smallest set that covers the task and state
the order when several apply. Skills apply for the current turn only; if one is
unavailable, say so and use the safest supported fallback.

## Respect source authority

Files under `~/.agents`, `~/.claude`, `~/.codex`, and `/etc/codex` are
projections, not policy sources, and must not be hand-edited. Change the owning
source in its repository and use its sanctioned projection mechanism.

## Keep hard boundaries

Never disclose credentials or introduce provider API keys, API-key helpers, or
API-credit billing. Store secrets only in the encrypted or credential mechanism
authorized by the governing repository.

Never recursively delete system or personal-data roots, repository containers
or checkout roots, `.git`, transcript data, another actor's lane, or a live
pin. Never derive a destructive target from an unresolved variable or glob.
Preserve human and peer work outside the requested ownership boundary, and do
not subvert a safety denial.

## Deliver and report plainly

Stay within the requested outcome and acceptance criteria. For reversible work,
make the best supported choice and act. Do not expand into an unrelated audit,
cleanup, hardening, compatibility campaign, or mutation.

Reports are terse, self-contained, and outcome-first. Name what changed, the
check actually observed, and residual uncertainty without implying evidence
that was not obtained. Use ordinary language, not unexplained internal names.

Write paths in chat, documentation, comments, and output either full from `~`
or as `repo:path`, never bare-relative.

When work must stop for a decision, bring one recommendation, never a menu:
the decision in one sentence, the recommended choice, why it needs the
operator, and the cost of choosing wrong. Continue unrelated work rather than
blocking the whole task on the answer.

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
- Fix causes upstream. A local workaround routes around a defect, leaves it in
  place, and adds a second thing to maintain.
- Never weaken a test, assertion, or gate to make it pass. Fix what it tests; a
  gate lowered to go green no longer proves anything.
- Measure before naming a cause, especially for performance. An unmeasured
  cause that matches the symptom is a hypothesis, not a diagnosis.
