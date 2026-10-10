---
name: convo
description: >-
  Recall past agent work, decisions, commands or session IDs across Claude Code and Codex transcripts with the indexed convo CLI, instead of searching transcript storage.
grounded: 2026-10-10
written: 2026-10-10
---

# Recall past work with convo

Never recursively scan transcript storage with raw tools; open what `convo` points at.

## Find
- `convo <words>` ranks sessions, each with its best message and an `[id]`.
  The words must share one message; when none does, sessions are ranked by
  how many words they cover.
- Tokens with punctuation (`c289-ko-bottom`, `tools/x.ts`) match as phrases.
  Use `-x '<literal>'` for exact strings, ids and error text.
- Narrow with `-r user|assistant|thinking|tool|system`, `-t Bash`, `-p <project>`,
  `-s <session or subagent id prefix>`, `--provider claude|codex` and
  `--since`/`--until 12h|3d|2w|YYYY-MM-DD`.
- `-r user` holds typed prompts and task briefs; injected harness text is `system`.
- Filters without words list the newest messages: `convo -r user --since 1d`.
- `-m` lists messages instead of sessions, `--json` feeds tools, `--full` prints
  whole messages.

## Open
- `convo show <id> -C 3` prints the message in full with its neighbours, session,
  path and line.
- `convo session <id prefix>` lists a session's transcripts, its first ask and the
  other sessions that mention it.
- Read a raw transcript only at the path and line that `show` printed.

## Judge
- Exit 0 means found, 1 a conclusive miss, and 2 inconclusive (index busy, root
  missing, `-u`) or bad usage. Retry or narrow after 2; it never proves absence.
- Only messages and tool calls are indexed, never tool output, so text seen only
  in a command's output is a miss.
- Every search refreshes the index first. Calls to convo itself are not results,
  and the current session ranks last.
- A hit is a recorded claim. Check the speaker, the date and any later reversal,
  and verify consequential facts against current source.
- For a verdict, add words like `landed`, `refuted` or `decided` to the topic.

Maintenance (`index --full`, `compress`, `restore`), the corpus layout and the
skill-usage SQL are in `references/notes.md`. Everything else is in `convo --help`.
