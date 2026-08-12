# Global agent instructions

Durable machine law for every session and every provider. Self-contained: no
rule below depends on a linked document, daemon, hook, orchestration system, or
coordination protocol. Optional behavior is supplied only by the switchboard
module that owns it.

## Delivery
For reversible work, make the best supported decision and act. Run the
nearest existing relevant check once, fix the concrete failures it shows,
report residual uncertainty, and stop when the requested outcome exists.
Never invent verification apparatus to make a report look stronger; report
the check you ran and what it observed, or say plainly that none exists.
Reports are plain sentences, outcome first — no schemas, no ceremony.

## Proportional verification
Verification buys down a named risk; it is not a search for certainty. Before
running checks, choose the smallest evidence that could change the delivery
decision and the lowest deterministic layer that proves each claim. Once that
evidence passes and the requested outcome exists, stop. For reversible work,
unplanned verification or diagnosis after the relevant checks defaults to at
most one fifth of the expected delivery window. Exceed that only for a
reproducible product failure or a named risk to security, data integrity, an
irreversible migration, or a published contract.

Hermeticity is a means, not the goal. Do not build a new harness, broaden a
probe, or chase guarantees whose absence would not change the shipping
decision. Unless the user changes them, acceptance criteria freeze when
delivery begins: a new observation may reveal a concrete defect, but may not
silently create a new guarantee. Preserve and defer non-blocking uncertainty
with the evidence already obtained.

## Tests and release gates
Put each claim at the lowest layer that can prove it deterministically: pure
logic first, controlled integration for seams, and full-stack end-to-end tests
only for critical journeys. Do not make one test simultaneously prove unrelated
concerns such as networking, persistence, rendering, performance, and external
availability. Control clocks, randomness, state, versions, and owned
dependencies where they affect correctness; isolate public networks, wall-clock
timing, schedulers, GPUs, and shared services from correctness gates. Test owned
behavior and integration boundaries, not dependency internals or platform
conformance already owned upstream.

A check is a release gate only when it was named before release, is reproducible,
is attributable to the product, and would change the shipping decision. A new
concrete product failure may still block; its diagnostic does not thereby become
a permanent gate. Timing, infrastructure, environment, and probe failures are
diagnostic until isolated. A gating check does not retry a failure into success;
diagnostic retries stay visible and the result stays flaky. Demote a flaky gate
until repaired; give ambiguity one bounded diagnostic pass, and do not lengthen
a timeout without evidence that legitimate work changed.

## Bounded checks fail visibly
Every bounded check has one accountable supervisor, explicit phase or case
deadlines, and visible progress within its expected window. The supervisor owns
and reaps every child process; a shared whole-suite timeout is not a substitute
for phase deadlines. On first failure, stop the affected lane and preserve the
available error, logs, and relevant artifacts. Silence past the expected window
is a failure to surface immediately, never a reason to wait indefinitely.

## Blocked ≠ stopped
A denial is information about the path, not the goal: never retry verbatim,
never subvert intent — find the nearest COMPLIANT move that still advances.
Verify a blocker's load-bearing assertion before accepting OR overriding it.
At a hard wall (permission system, another agent's live dependency): stop,
hand the user the finish as ONE command, and say exactly why.

## Repository layout — container/worktree (safety-critical)
`~/code/<project>/` is a container, never itself a checkout. `main/` is the
clean checkout and is NEVER edited directly, by anyone. All work happens in a
sibling worktree:

    git -C ~/code/<project>/main worktree add ~/code/<project>/wt-<slug> -b <slug>
    # edit + commit in the worktree, then FROM the worktree:
    safe-push --to main
    git -C ~/code/<project>/main pull --ff-only

Then remove the worktree and delete the branch — a landed lane that leaves
its worktree behind is not done. Name the leaf `wt-<slug>` (the prefix is
what the enforcement guard carves out); don't repeat the project name in the
slug. Dirty state in any `main/` is human work-in-progress: never commit,
stash, reset, or clean it — `wt-rescue` relocates it intact if remediation
is truly needed.

## Launch-critical repos — agents never edit the primary
`~/code/fram`, `~/code/north`, and `~/code/beagle` are read live by daemons
and rebuilds: a half-finished edit in the primary checkout is a broken engine
for everyone. Agents editing these ALWAYS work in a `wt-<slug>` sibling.
General rule: if something launches from a checkout, that checkout is
production — edit it in a worktree and land through a ref.

## Push — safe-push, never raw
Commit at coherent checkpoints, then `safe-push` — never raw `git push`,
never `git commit && git push` chained (the pre-commit hook must run first).
Stage by enumerating paths; `git add -A` sweeps in other agents' work. STOP
for: a flagged secret (fix the leak, never push it), force-push or rewrite of
published history, private-to-public exposure, or another agent's in-flight
WIP. Origin carries main only (plus tags); worktree branches are local and
ephemeral; never publish a feature branch name.

## Rebuilds — use the sanctioned wrapper
Agents may run `firn rebuild` after the relevant checks pass and their own
changes are committed. It builds a COMMIT SNAPSHOT (`rev=HEAD`), so concurrent
uncommitted work cannot enter the generation. Raw `nixos-rebuild`, `nh`, and
`firn update` remain user-only. Build-only verify:
`nix build --no-link`.

In `~/code/nixos-config`, `.bnix` is the write interface and `.nix` is
generated by `./scripts/firn-build`: editing a `.nix` that has a sibling
`.bnix` is work that gets silently overwritten. Dev environments activate via
direnv (`use flake` in `.envrc`) — never bare `nix develop` / `nix shell`.

## Agent config is projected, never hand-edited
Everything under `~/.agents`, `~/.claude`, `~/.codex`, and `/etc/codex` is a
PROJECTION. Nothing there is a policy source, and editing it is a change that
the next activation silently reverts. Which pieces of context, hooks, and
skills are live is decided by the `agents` switchboard (`agents status` to
see, `agents on|off <name>` to change) — a session gets exactly what the
switchboard turned on and nothing else. To change what a piece SAYS, edit the
source file in its owning repository and commit it there; `agents path <name>`
prints that file. Default state is off: absence of a hook or doc is the
configured answer, not a fault to route around.

## External code — license first
Before leveraging ANY code you didn't write (`~/code/reference`, forks,
vendored snippets): check for specified license terms first. If none are
specified, treat the source as MIT-licensed. Flag copyleft or explicitly
restrictive terms to the user BEFORE building on them. Attribution and license
text travel with copied code. `~/code/reference/` is read-only context — never
edit it, never build features there, and never take a worktree in it. Reading a
reference implementation to understand a protocol is always fine; copying its
expression is a licensing decision, not a style one.

## Internal notes — docs/private/, never public docs/
Agent notes, status, scratch, and handoffs go in gitignored `docs/private/`
in the repo they concern. Public `docs/` is end-user-facing only.

## Searching past conversations — `convo`, never a raw scan of north-data
`convo <terms>` full-text-searches every transcript (both providers, every
account) and prints when, which project, which session, a snippet, and the
`path:line` to open. `convo session <uuid>` locates one session's transcripts;
`convo -x '<literal>'` is exact match. It refreshes incrementally at query
time, so it is never stale and costs ~0.1s when nothing changed.
NEVER `rg`/`grep` across `~/code/north-data` or `~/.local/state/north`: they
are the SAME ~99 GB tree behind a symlink, so naming both scans it twice, and
`--hidden` walks the `.git` dirs on top. One such sweep measured 3.5 GB RSS
and a quarter of the machine. Scan raw only after `convo` names the file.

## Paths — full and ~-anchored, always
Every path you write (chat, docs, comments, output): full from `~`, never
bare-relative. In docs, prefer `repo:path` over absolute checkout paths.
Touching a repo you're not cwd'd into: read its root AGENTS.md first.

## Billing — subscription entitlements only, never API credits
NEVER introduce `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, provider API-key
helpers, or API-credit billing into env, settings, or harness code. Provider
adapters use the authenticated subscription surface of the provider.

## rm on variable paths
Never write `rm … "$VAR"/glob` — an unset `$VAR` expands to a bare-root
delete. Use `rm -rf "${VAR:?}"/…`, or remove-and-recreate the scratch dir by
its literal absolute path. Fix the command, not the guard.

## Background shells — always accountable
Every background shell or monitor you start has ONE named purpose you can
state on demand; "what are my shells" is answerable from memory, never by
archaeology. A bounded task silent past its expected window is presumed
rotten — kill it and retry tighter rather than waiting longer. A kill and a
new launch never share one command (pattern kills snipe the wrapping shell).
Reap a finished lane's shell in the same cycle you consume its output.

## Tone
Terse by default — no filler, no hedging, full sentences; brevity comes from
content selection, never compression tricks. Never tell the operator to
sleep, rest, or step away; their schedule is not yours to manage.

## Code — durable norms
- Removal means absence: an asked-for removal deletes the entire live-tree
  surface — no tombstones, shims, "removed" errors, or commentary. Git
  history is the recovery mechanism. Finish with a tracked-tree token search
  for the removed name, and remove the tests of the removed thing with it.
- Personal projects break forward: current main is the supported line; a
  breaking change migrates every in-tree consumer in the same change. No
  compatibility machinery for hypothetical legacy clients.
- Incidental code walks down the ladder (repo already does it → stdlib →
  platform → existing dep → smallest block); core code is hand-rolled
  deliberately. Correctness, error handling, and security are never
  laddered away.
- A comment states a constraint the code cannot say. Narrative (how found,
  outputs, dates) belongs in the commit message, not the code.
