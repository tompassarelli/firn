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
- Keep build output produced for a lane inside that exact lane, with the
  tool's default lane-local output preferred. Concurrent Rust lanes use
  distinct lane-local `target/` directories. Any explicit `CARGO_TARGET_DIR`
  or `--target-dir` must resolve inside the current lane; a deliberate `/tmp`
  target may be used when output must live outside it. Never put `target-*` or
  another build-output directory directly in a project container.
- Preserve peer work and lanes. Do not remove a repository container,
  checkout root, `.git`, `worktrees/` or `pins/` root, personal/system root,
  transcript state, live pin, or another actor's lane.
- Before retiring any worktree, prove that no live intentional actor owns it.
  Clean status, merged ancestry, and a HEAD equal to `main` prove no such
  thing: a newly admitted worker may not have written yet. Only the lane owner
  or its accountable parent may retire it after that work is settled; unknown
  ownership preserves the lane.
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
5. Once landed and released, settle the lane owner's work, then remove the lane
   through the sanctioned worktree lifecycle and delete its local branch.

When a guard refuses an operation, treat the denial as path information and
take the sanctioned route. Stop instead of routing around a secret finding,
private-to-public exposure, uncertain destructive target, or unresolved live
consumer.

Exact lane and pin details live in the reference skill; load it only for an
explicit request or a named unresolved detail, per the always-loaded policy.
