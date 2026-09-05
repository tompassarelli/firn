---
name: project-structure-distilled
description: >-
  Organize project files by real authority, lifecycle, and retrieval needs, including data pipelines and handoff layouts.
---

# Project structure

Trace actual sources, producers, consumers, retained state, and rerun commands
before choosing directories. Add a boundary only when authority, lifecycle,
retrieval, or retention differs. Preserve native language and build conventions.

For data workflows, preserve immutable inputs or identities and the transforms
needed to trace results. Keep checkpoints only when they save expensive work
or support inspection, recovery, or handoff. Ordinary software does not need
data-stage or experiment folders.

Use meaningful names and repository path conventions. Migrate every affected
consumer, script, build rule, test, and document together.

Finish when the native workflow runs and a newcomer can locate source, inputs,
outputs, disposable work, and the rerun path. For naming and data examples,
use `agents path project-structure-reference`.
