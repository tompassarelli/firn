---
name: convo-distilled
description: >-
  Search past agent conversations with the `convo` CLI — full-text across every
  Codex and North transcripts on this machine, including configured
  `CODEX_HOME` stores such as the pooled runtime. Use this
  whenever the answer might live in an earlier session: "when did we discuss
  X", "what did I decide about Y", "find that session", recovering a prior
  ruling, tracking down where a defect was first named, or locating a session
  by its id. Reach for this INSTEAD of grep/rg/find over ~/code/north-data or
  ~/.local/state/north — those paths hold a 77 GiB transcript corpus and a
  single unscoped ripgrep there measured 3.5 GB of RSS and a quarter of a
  24-core machine, while the same lookup through convo costs 31 MB and 0.4 s.
---

# Search conversations

Use `convo` for conversations and `rg` for code. Never recursively search the
transcript corpus with `rg`, `grep`, `find`, `fd`, or `ag`; use `convo` to name
one transcript, then raw tools only on that bounded file or narrow directory.

1. Search with `convo <terms>` or exact text with `convo -x '<literal>'`. Each
   search refreshes account stores and configured live Codex homes first.
2. Narrow with filters; use `convo session <uuid>` for a known session and
   `--json` for structured consumers.
3. Treat hits as recorded claims and verify load-bearing conclusions against
   the current tree.

The index refreshes incrementally by default. If refresh cannot acquire its
lock or an explicitly configured root is unavailable, the command reports the
result as inconclusive (exit 2), never as absence; restore the root or retry
after the writer finishes. Do not rebuild, compress, or restore it merely to
answer a search.
Route unresolved command or maintenance detail to the reference skill only for
an explicit request or a named unresolved question.
