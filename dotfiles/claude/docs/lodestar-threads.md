# Lodestar threads — claim-native format

**Threads are claim-native (as of 2026-06-15 — the big cutover).** A thread file
is `@<id>` + `predicate  object` triple lines + `---` + prose body; refs are
`@id`, literals are EDN. There is **no `state` enum** — lifecycle is *derived*
from claims: `committed` (accepted/in-play), `outcome` (done), `abandoned`
(canceled), `driver` (active now), `depends_on` (blocked). A fresh capture is
**`committed`** by default. Relatedness is `relates_to @<thread>` (no string
tags — former tags are `@topic-*` threads). ids are `2026-06-15-150040`.

**There is ONE CLI/engine: `lodestar`** — `los` is **gone entirely**: thread ops
are `lodestar`, and time tracking is **`lodestar clock`** (claim-native sessions
— `session_of`/`start_time`/`end_time` rolling up to a thread for estimate-vs-
actual; Clockify is an on-demand sync projection via `clock sync`). Full spec:
`~/code/lodestar/docs/claim-native-redesign.md`.
