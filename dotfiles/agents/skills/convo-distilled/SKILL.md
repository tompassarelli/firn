---
name: convo-distilled
description: >-
  Find past agent conversations, decisions, or session IDs with the indexed convo CLI. Use it instead of recursive searches of transcript storage.
---

# Search conversations

Use `convo <terms>`, `convo -x '<literal>'`, or
`convo session <uuid>`. Narrow by role, project, date, and result count;
use `--json` for structured output.

Never recursively scan transcript storage with raw search tools. After
`convo` identifies a source, inspect only that file or a narrowly bounded
directory. Search repository code with `rg`.

Ordinary searches refresh configured account stores incrementally. A blocked
refresh or missing configured root yields an inconclusive result (exit 2),
not proof of absence. Restore access or wait for the writer; do not rebuild,
compress, or restore the corpus merely to search it.

Treat hits as recorded claims and verify consequential conclusions against
current source. For filters, recovery, and archive behavior, use
`agents path convo-reference`.
