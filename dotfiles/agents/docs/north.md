# north — thread format + writing safely under concurrent agents

## Thread files (fact-native)

A thread file is `@<id>` + `predicate  object` triple lines + `---` + prose
body; refs are `@id`, literals EDN. Lifecycle is DERIVED from facts
(committed/outcome/abandoned/driver/depends_on) — no state enum; a fresh
capture is committed. Relatedness is `relates_to @<thread>` (no string tags —
former tags are `@topic-*` threads). ids: `2026-06-15-150040`. Time: `north clock`
(fact-native sessions; Clockify is an on-demand projection via `clock sync`).
Full spec: north:docs/fact-native-redesign.md.

## Done-bars — completion evidence on threads

Two predicates, both `cardinality multi`, `value_kind literal`:

- **`done_when`** — one completion criterion per fact; phrasing convention "probe + expected result" (e.g. `"north validate exits 0"`, `"firn build + validate green"`). Threads SHOULD carry these by commit time.
- **`bar_evidence`** — one observed probe result per fact, QUOTING its bar: `"<bar> → <observed result>"` (e.g. `"north validate exits 0 → exit 0, 2026-07-11"`). Pairing is text containment — a bar is ✓ when some evidence fact quotes it.

**Friction gradient:**
- **capture** — zero ceremony; no bars required at jot time.
- **commit/dispatch** — bars expected; `north dispatch` warns on bar-less committed threads and injects "define your done bar first" into worker contracts.
- **outcome** — `north tell <id> outcome ...` on a barred thread echoes the bars (reminder, never a reject).
- **needs-review** — flags (i) committed+driven threads without `done_when`, (ii) outcomes on barred threads with ○ (unquoted-by-evidence) bars, each marked ✓/○.

Example:
```
north tell 2026-07-11-120000 done_when "north validate exits 0"
north tell 2026-07-11-120000 bar_evidence "north validate exits 0 → exit 0, 2026-07-11"
```

`north schema thread` shows `done_when` metadata once declared. Full spec: north:docs/operating-manual.md §Done-bars.

## Writing safely under concurrent agents

north threads are backed by the North fact graph (engine `~/code/fram`;
canonical log `~/.local/state/north/facts.log`). Assume **other agents
may be editing concurrently**:

**Session-start handshake (before coordinating north, mirrors beagle-doctor):**
run `north doctor`. If it reports DOWN/DEGRADED, run
`north up` to start the coordinator on the canonical log.
(Optional heartbeat: `/loop 10m north up` keeps it alive.)

- Creating/editing a thread `.md` is fine — distinct files don't collide. After
  editing, run `north import` to fold edits into the fact
  log (idempotent; safe to run anytime).
- **Do not run `north export` during concurrent work** — it regenerates
  `threads/` from the log and would clobber another agent's un-imported edits.
  (The engine refuses if files diverge, but don't rely on it.)
- **Serialized fact writes go through the coordinator** via `north tell <id>
  <pred> <value>` / `retract <id> <pred> <value>` (alias: untell) — these route to the running
  daemon (serialized, rule-checked, retries on conflict). Do NOT use `north
  set`, which appends the log directly and races. For creating whole new threads,
  `north capture "<title>"` (fact-first) or file-edit + `import` is fine
  (distinct files don't collide); for field changes on existing threads under
  concurrency, prefer `tell`.
- Reads are instant off the warm coordinator (`north up`): ready / blocked /
  leverage / validate in ~1ms.

## Session state lives on threads — no markdown dumps (dogfood protocol)

The graph is the working memory, not your context window. The recurring failure
this kills: session state written as `docs/private/SESSION-DUMP-*.md`, recovered
by pasting files into a fresh context — while the substrate built for exactly
this sits unused (and unwatched: two integrity regressions went unnoticed for
days because nobody lived in the graph).

1. **Substantive work runs on a thread.** Find-or-capture it at session start;
   `tell <id> driver @claude-code` when you actually start pushing.
2. **State = facts, not dumps.** Milestones/findings → `tell <id> progress
   "..."`; durable lessons → `tell <id> learning "..."`; finish → `outcome`.
   Writing a `SESSION-DUMP-*.md` is a protocol violation — the thread IS the
   handoff; the next session reads `north show <id>`, not a file.
3. **Agent briefs are thread refs.** When spawning an agent for thread work,
   the brief is "read `north show <id>`, write `progress` back" plus only the
   delta the thread doesn't hold — not a restatement of everything you know.
4. **Findings about the substrate go IN the substrate.** Found a bug mid-work?
   `capture` it, keep moving. Discovery-by-inhabiting is the point.
