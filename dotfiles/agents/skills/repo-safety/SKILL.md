---
name: repo-safety
category: git
description: >-
  Use before editing, committing, or pushing in any ~/code repository: where
  agents may write (a worktree, never a `main` checkout), how work lands
  (safe-push, enumerated paths), and which commands are refused outright. The
  companion notice for the worktree, blind-stage, and tripwire guards.
hooks:
  - worktree-guard
  - git-blind-stage-guard
  - tripwire-guard
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

**Destructive and credential commands.** A recursive delete is judged by what
would be lost, not by where the path is. Refused outright, in every mode: `/`,
`$HOME`, a system root, a personal category root like `~/Pictures`, a `main/`
checkout, a project container, `~/code/*-data`, `~/.local/state/north`, any
`.git` or checkout root, and any `wt-<slug>` worktree your session is not
working in — another lane may be live in it. Never write `rm … "$VAR"/glob`
either: an unset `$VAR` expands to a bare-root delete, so write the literal
path or guard it as `"${VAR:?}"`.

Deletes that lose nothing pass without friction: a path that does not exist,
`~/.cache` and the temp hierarchy, `node_modules` and friends, anything git
reports as ignored, and anything tracked and clean. In between — untracked work
inside a repo, personal data, a path the guard cannot classify — the guard asks
you in an interactive session and refuses in an unattended one; the reason names
`north config guards off` for when the loss is reviewed and intended.

Shell access to `.ssh/`, `.aws/`, `*.pem`, and key files is refused.

A denial is information about the path, not the goal: take the worktree, name
the paths, use `safe-push`. If a guard is genuinely wrong about your case, say
so to the user rather than routing around it.
