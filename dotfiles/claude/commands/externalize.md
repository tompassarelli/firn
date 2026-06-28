---
description: Externalize bulky CLAUDE.md sections into docs/ with breadcrumb pointers
argument-hint: "[path-to-file]   (default: ./CLAUDE.md)"
---

# /externalize

Target file: **$1** if given, else `./CLAUDE.md`.

Goal: shrink a bloated instruction file by moving situational, bulky content into
`docs/<topic>.md`, leaving a short, indexed breadcrumb in its place. Nothing is
deleted — content is relocated and referenced. This is `Extract Method` for prose.
Execute directly; do not ask for approval first.

## Step 1 — Read & classify

Read the target file. Split it into top-level sections (by heading). Classify each:

**KEEP inline** (do NOT externalize):
- Security / safety rules, hard constraints, one-line laws.
- Anything load-bearing on most turns (the rules an agent must see every time).
- Short sections (< ~15 lines) — a hop costs more than it saves.
- The project intro / one-line orientation at the top.

**EXTRACT** (move to docs/):
- Long procedural playbooks, runbooks, step-by-step recipes.
- Worked examples, code samples, large reference tables / enumerations.
- "When doing <X>-type task" deep-dives that only matter in narrow contexts.
- Troubleshooting / recovery sections.
- Anything > ~40 lines that is situational rather than always-on.

## Step 2 — Execute

For each EXTRACT section:
1. Create `docs/` if missing.
2. Write the full section verbatim to `docs/<slug>.md`, prefixed with an H1 title.
   `<slug>` = kebab-case of the heading.
3. Replace the section in the target file with a breadcrumb:

   ```markdown
   ## <Original Heading>
   → [`docs/<slug>.md`](docs/<slug>.md)
   **Read when:** <concrete triggers — which files / task-types pull this in>.
   ```

   Optionally one line of gist above "Read when" if the topic isn't self-evident.

## Rules

- Preserve original section ORDER in the target file.
- Idempotent: a section already in breadcrumb form (`→ [docs/...]`) is skipped.
- Never externalize KEEP-class content, even if long.
- "Read when" triggers must be concrete (file globs, task verbs), not vague —
  they are the index an agent greps to decide whether to open the doc.
- If inside a git repo, after writing, remind me to `git add` the new docs/ files
  (some tools — e.g. Nix flakes — ignore untracked files).
- Report a summary: N sections externalized, M kept, lines saved in the main file.
