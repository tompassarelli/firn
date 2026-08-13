---
name: repo-safety
category: git
description: >-
  Use before editing, committing, or pushing in any ~/code repository: where
  agents may write (a lane under `worktrees/`, never a `main` checkout and
  never a `pins/` checkout), how work lands (safe-push, enumerated paths), and
  which commands are refused outright. The companion notice for the worktree,
  blind-stage, and tripwire guards.
hooks:
  - worktree-guard
  - git-blind-stage-guard
  - tripwire-guard
  - session-kill-guard
---

# repo-safety — where agents may write, and how work lands

Hooks enforce every rule below: a violation is a refused tool call, not a
warning. They exist so no half-finished agent edit sits in a checkout that
something else launches from.

**Never edit a `main` checkout.** `~/code/<project>/` is a container holding
three slots, and the directory is the lifecycle policy: `main/` is the clean
checkout and is never edited directly; `worktrees/<slug>/` are the ephemeral
lanes agents work in; `pins/<name>/` are checkouts something outside the repo
consumes. Work in a lane — the `worktrees/` parent is exactly what the guard
carves out, so the leaf is a bare slug:

```
git -C ~/code/<project>/main worktree add ~/code/<project>/worktrees/SLUG -b SLUG
# edit + commit in ~/code/<project>/worktrees/SLUG, then FROM the lane:
safe-push --to main
git -C ~/code/<project>/main pull --ff-only
```

Then remove the worktree and delete the branch — a landed lane under
`worktrees/` that leaves its tree behind is not done. That rule stops at
`worktrees/`: a pin is never "done" and is never swept. Dirty state in a
`main/` is human work-in-progress: never commit, stash, reset, or clean it
(`wt-rescue` relocates it intact into `worktrees/rescue-<ts>`).

**Never write into `pins/`.** A pin is protected because something outside the
repo consumes it — `pins/<name>.pin` names what — not because dirt in it is
someone's WIP. Edits, writes, and deletes under `pins/` are refused, manifest
included. Reads are fine, and so is the one sanctioned mutation: re-pointing
the pin with `git -C ~/code/<project>/pins/<name> checkout <ref>`. If a pin
looks wrong, ask the human; never cut a lane from it.

**Stage by enumerating paths.** `git add -A`, `git add -u`, `git add .`, and
`git commit -a` are refused: blind staging sweeps in another agent's in-flight
work.

**Push through `safe-push`, never raw.** No raw `git push`, no
`git commit && git push` chain (pre-commit must run first), no force-push or
rewrite of published history. Origin carries main plus tags; lane branches stay
local (a pin has no branch — it is detached HEAD).

**Signals stay scoped to processes you started.** Broadcast kill (`kill -1`),
user-wide sweeps (`pkill -u`/`killall -u` with no pattern), compositor kills
(`pkill niri`), and login-session teardown (`loginctl terminate-*`,
`systemctl --user exit`, stopping `user@*`) are refused: one such call takes
down the desktop session, the user manager, and every other agent at once.
Signal a specific PID (`kill <pid>`) or a unique pattern
(`pkill -f '<unique-pattern>'`); session teardown is the operator's call. Code
that must reap a whole process subtree runs as PID 1 inside its own PID
namespace (`unshare --user --map-current-user --pid --fork --kill-child`) —
never `kill(-1)` in the caller's namespace.

**Destructive and credential commands.** A recursive delete is judged by what
would be lost, not by where the path is. Refused outright, in every mode: `/`,
`$HOME`, a system root, a personal category root like `~/Pictures`, a `main/`
checkout, a project container, a container's `worktrees/` or `pins/` root,
`~/code/*-data`, `~/.local/state/north`, any `.git` or checkout root, any pin
under `pins/`, and any `worktrees/<slug>` lane your session is not working in —
another lane may be live in it. Never write `rm … "$VAR"/glob`
either: an unset `$VAR` expands to a bare-root delete, so write the literal
path or guard it as `"${VAR:?}"`.

Deletes that lose nothing pass without friction: a path that does not exist,
`~/.cache` and the temp hierarchy, `node_modules` and friends, anything git
reports as ignored, and anything tracked and clean. In between — untracked work
inside a repo, personal data, a path the guard cannot classify — the guard asks
you in an interactive session and refuses in an unattended one; the reason names
`north config guards off` for when the loss is reviewed and intended.

Credential files may be passed to purpose-built authentication commands.
In particular, `ssh-add <key>` may load any identity, and SSH-family identity
options may name any key. Authentication is not disclosure: do not print,
copy, upload, or pipe private-key contents into another process or tool output.

A denial is information about the path, not the goal: take the lane, name the
paths, use `safe-push` — except for a pin, where the compliant move is asking
the human, never cutting a lane from it. If a guard is genuinely wrong, say
so to the user rather than routing around it.
