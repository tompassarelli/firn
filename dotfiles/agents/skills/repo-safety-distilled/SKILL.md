---
name: repo-safety-distilled
description: >-
  Use before editing, committing, or pushing in any ~/code repository: where
  agents may write (a lane under `worktrees/`, never a `main` checkout and
  never a `pins/` checkout), how work lands (safe-push, enumerated paths), and
  which commands are refused outright. The companion notice for the worktree,
  blind-stage, and tripwire guards.
---

# Repository safety, distilled

Work only in an owned `~/code/<project>/worktrees/<slug>` lane. A `main/`
checkout is human/launch state and every `pins/<full-object-id>/` checkout is
immutable consumer state.

## Hard boundaries

- Never edit, stash, reset, clean, or commit a dirty `main/`; use `wt-rescue` to
  relocate human work intact. Never mutate or repoint a pin checkout.
- Preserve peer work and lanes. Do not remove a repository container,
  checkout root, `.git`, `worktrees/` or `pins/` root, personal/system root,
  transcript state, live pin, or another actor's lane.
- Stage only enumerated paths. Do not use `git add -A`, `git add -u`,
  `git add .`, or `git commit -a`.
- Publish with `safe-push`, never raw `git push`, force-push, or rewritten
  published history. Let pre-commit finish before a separate publish command.
- Signal only processes you started by exact PID or unique scoped pattern;
  never tear down a user session or broadcast across it.
- Never print, copy, upload, or pipe credential contents. Purpose-built
  authentication commands may load credential files without disclosure.

## Minimum lane workflow

1. Create an owned branch and worktree from the clean project `main` checkout.
2. Edit and verify in that lane, staying within the requested ownership paths.
3. Stage each intended path explicitly and commit one coherent checkpoint.
4. From the lane, run `safe-push --to main`; then fast-forward the clean
   `main/` checkout.
5. Once landed and released, remove the lane through the sanctioned worktree
   lifecycle and delete its local branch.

When a guard refuses an operation, treat the denial as path information and
take the sanctioned route. Stop instead of routing around a secret finding,
private-to-public exposure, uncertain destructive target, or unresolved live
consumer.

For exact lane and pin commands, pin sidecar/retirement procedure, destructive
classification, tripwire exceptions, and signal examples, run
`agents path repo-safety-reference` and read the returned skill completely
before performing those detailed operations.
