---
name: repo-safety
category: git
description: >-
  Use before editing, committing, or pushing in any ~/code repository: where
  agents may write (a worktree, never a `main` checkout), how work lands
  (safe-push, enumerated paths), and which commands are refused outright. The
  companion notice for the worktree, blind-stage, and tripwire guards.
---

# repo-safety — where agents may write, and how work lands

Hooks enforce every rule below: a violation is a refused tool call, not a
warning. They exist so no half-finished agent edit sits in a checkout that
something else launches from.

**Never edit a `main` checkout.** `~/code/<project>/` is a container; `main/`
is the clean checkout and is never edited directly. Work in a sibling worktree,
named `wt-<slug>` — that prefix is exactly what the guard carves out:

```
git -C ~/code/<project>/main worktree add ~/code/<project>/wt-<slug> -b <slug>
# edit + commit in the worktree, then FROM the worktree:
safe-push --to main
git -C ~/code/<project>/main pull --ff-only
```

Then remove the worktree and delete the branch — a landed lane that leaves its
worktree behind is not done. Dirty state in a `main/` is human work-in-progress:
never commit, stash, reset, or clean it (`wt-rescue` relocates it intact).

**Stage by enumerating paths.** `git add -A`, `git add -u`, `git add .`, and
`git commit -a` are refused: blind staging sweeps in another agent's in-flight
work.

**Push through `safe-push`, never raw.** No raw `git push`, no
`git commit && git push` chain (pre-commit must run first), no force-push or
rewrite of published history. Origin carries main plus tags; worktree branches
stay local.

**Destructive and credential commands.** Recursive deletes outside the cwd repo
and `/tmp` are refused, `rm -rf` of `/`, `/home`, or `$HOME` always. Never write
`rm … "$VAR"/glob` — an unset `$VAR` expands to a bare-root delete. Shell access
to `.ssh/`, `.aws/`, `*.pem`, and key files is refused.

A denial is information about the path, not the goal: take the worktree, name
the paths, use `safe-push`. If a guard is genuinely wrong about your case, say
so to the user rather than routing around it.
