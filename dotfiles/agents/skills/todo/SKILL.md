---
name: todo
category: notes
description: >-
  Use when writing a handoff, todo list, backlog, or parked design note:
  those files live in ~/code/todo/main/handoffs/ — never in a repo checkout,
  north-data, or the home directory.
---

# todo — where working notes live

`~/code/todo/main/handoffs/` is the single home for cross-session working
notes: handoffs, todo lists, backlogs, and parked design notes. This applies
even when a note concerns one repo — a handoff about beagle still lives here,
not in beagle.

**One item = one `.md` file, or one directory for multi-file handoffs.**
Follow the existing naming: `<topic>-handoff-NN` for handoffs
(`north-handoff-primitives-01.md`), plain descriptive names for notes and
backlogs (`oh-my-pi-harvest-backlog.md`).

What does NOT belong here:

- Runtime state and machine-managed data — data dirs (`north-data`, …).
- End-user documentation — the owning repo's public `docs/`.
- Ephemeral scratch mid-task — the session scratchpad.

`~/code/todo` is a plain directory, not a git repository; write files
directly. Paths inside notes follow the global rule: `repo:path` form for
repo files, `~`-anchored for fixed locations.

When finishing a session with undone work, leave the handoff here — the next
session's first move is reading it.
