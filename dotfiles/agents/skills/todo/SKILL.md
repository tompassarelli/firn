---
name: todo
category: notes
description: >-
  Use when writing a handoff, todo list, backlog, or parked design note:
  those files live flat in ~/code/todo/ — never in a repo checkout,
  north-data, or the home directory.
---

# todo — where working notes live

`~/code/todo/` is the single home for cross-session working notes: handoffs,
todo lists, backlogs, and parked design notes. This applies even when a note
concerns one repo — a handoff about beagle still lives here, not in beagle.

**The folder stays FLAT** (its AGENTS.md is the authority): items sit at the
root — one `.md` file per item, or one directory for a multi-file handoff.
Never create a `main/` subdirectory or any other nesting layer; `~/code/todo`
is a plain directory, not a git repository or project container.

Follow the existing naming: `<topic>-handoff-NN` for handoffs
(`north-handoff-primitives-01.md`), plain descriptive names for notes and
backlogs (`oh-my-pi-harvest.md`).

What does NOT belong here:

- Runtime state and machine-managed data — data dirs (`north-data`, …).
- End-user documentation — the owning repo's public `docs/`.
- Ephemeral scratch mid-task — the session scratchpad.

Paths inside notes follow the global rule: `repo:path` form for repo files,
`~`-anchored for fixed locations. A completed item's file is deleted, not
archived — absence is the record that nothing is pending.

When finishing a session with undone work, leave the handoff here — the next
session's first move is reading it.
