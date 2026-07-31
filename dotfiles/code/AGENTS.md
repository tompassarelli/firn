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

## Repository layout — `~/code/<project>` is a CONTAINER, not a checkout

```
~/code/<project>/              container only — never itself a checkout
~/code/<project>/main/         the clean main checkout
~/code/<project>/wt-<slug>/    every working tree
```

**`main/` is never dirty.** Nothing is edited there, by anyone, ever. All work
happens in a `wt-<slug>` sibling and lands through a ref:

```
git -C ~/code/<project>/main worktree add ~/code/<project>/wt-<slug> -b <slug>
# edit + commit in the worktree, then land it:
git -C ~/code/<project>/main fetch ~/code/<project>/wt-<slug> <slug>:refs/heads/main
```

There is no longer a `~/code/worktrees/` root; a worktree is a sibling of
`main/`, so the project directory holds everything about that project and
nothing else does.

- **Name the leaf `wt-<slug>`.** The `wt-` prefix is load-bearing: it is what
  the enforcement guard carves out, so a directory without it is treated as
  part of the protected checkout.
- **Don't repeat `<project>` in the slug** — the container already names it
  (`wt-policy-graph`, not `wt-north-policy-graph`).
- **Billable-client repos keep their owner namespace** and take the same shape
  inside it: `~/code/client/<owner>/<project>/main` and
  `~/code/client/<owner>/<project>/wt-<slug>`. Client-confidentiality and clock
  guards still apply.
- **Reference repos get no worktrees** — `~/code/reference/` is read-only
  context; check out nothing extra there.
- **Ephemeral / tool-owned trees keep their tool-owned locations** (temp build
  trees, harness scratch). This policy governs durable human/agent worktrees.

### Referring to paths in docs — `repo:path`, not an absolute checkout path

Write **`north:cli/msg-cli.clj`**, not `~/code/north/cli/msg-cli.clj`.

An absolute checkout path is a hardcoded copy of the current layout, and it
rots the instant the layout changes. The `repo:path` form names the
repository and the path *inside* it, so it survives the checkout moving,
being renamed, or being cloned somewhere else entirely.

Absolute paths are still right for things that genuinely live at a fixed
location: `~/.local/state/north/…`, `/var/lib/…`, `/nix/store/…`.

### Enforcement

`~/.agents/hooks/launch-critical-worktree-guard.sh` refuses writes into a
protected checkout on `Edit|Write|MultiEdit` **and on `Bash`**. The Bash side is
not optional: the guard inspects Bash too — a Bash call carries
`tool_input.command`, not `tool_input.file_path`; enforcement on one entrance
is not enforcement.

Reads from `main/` stay allowed, as do `git worktree add` and
`git fetch <worktree> <branch>:refs/heads/main` — the guard must never trap a
lane with no compliant move.

Dirty state in any `main/` is human work-in-progress: agents never commit,
stash, reset, or clean it, and the guard denies destructive git operations
against a `main` checkout. A live-tuned preference file (niri's `config.kdl`)
is symlinked out of the checkout on purpose, so the tool that writes it
(`opacity`) commits its own one-file change instead of leaving dirt.

## Launch-critical repos — agents never edit the primary

`~/code/fram`, `~/code/north`, and `~/code/beagle` are **launch-critical**: a
running daemon or a rebuild reads them, so a half-finished edit in the primary
checkout is not a private work-in-progress, it is a broken engine for everyone.

**An agent editing any of these three works in a worktree, never in
`~/code/<project>` itself.** Use `EnterWorktree`, or
`git -C ~/code/<project>/main worktree add ~/code/<project>/wt-<slug>`.
The human's own primary checkout is unaffected by this rule.

The two repos fail differently, and both failures are real:

- **fram — hard deadlock.** `north up` refuses to launch on a tracked-dirty Fram
  checkout, on purpose: a coordinator serving a half-edited engine is worse than
  one that refuses. A dirty fram primary blocks coordinator restarts, which
  blocks adopting any rebuilt closure — one dirty primary stalls the whole
  machine.
- **north / beagle / nixos-config — silent exclusion.** `firn rebuild` builds a
  COMMIT SNAPSHOT, so uncommitted work is simply not in the generation. Nothing
  errors; the change just doesn't take, which reads as "the fix didn't work"
  and sends the next agent debugging code that never shipped.

The general rule the three repos are instances of: **if something launches from
a checkout, that checkout is production.** Edit production in a worktree and
land through a ref, the same as you would a deploy.
