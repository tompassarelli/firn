# tern — thread format + writing safely under concurrent agents

## Thread files (fact-native)

A thread file is `@<id>` + `predicate  object` triple lines + `---` + prose
body; refs are `@id`, literals EDN. Lifecycle is DERIVED from facts
(committed/outcome/abandoned/driver/depends_on) — no state enum; a fresh
capture is committed. Relatedness is `relates_to @<thread>` (no string tags —
former tags are `@topic-*` threads). ids: `2026-06-15-150040`. Time: `tern clock`
(fact-native sessions; Clockify is an on-demand projection via `clock sync`).
Full spec: ~/code/tern/docs/fact-native-redesign.md.

## Writing safely under concurrent agents

tern threads are backed by the Tern fact graph (engine `~/code/fram`;
canonical log `~/.local/state/tern/facts.log`). Assume **other agents
may be editing concurrently**:

**Session-start handshake (before coordinating tern, mirrors beagle-doctor):**
run `tern doctor`. If it reports DOWN/DEGRADED, run
`tern up` to start the coordinator on the canonical log.
(Optional heartbeat: `/loop 10m tern up` keeps it alive.)

- Creating/editing a thread `.md` is fine — distinct files don't collide. After
  editing, run `tern import` to fold edits into the fact
  log (idempotent; safe to run anytime).
- **Do not run `tern export` during concurrent work** — it regenerates
  `threads/` from the log and would clobber another agent's un-imported edits.
  (The engine refuses if files diverge, but don't rely on it.)
- **Serialized fact writes go through the coordinator** via `tern tell <id>
  <pred> <value>` / `retract <id> <pred> <value>` (alias: untell) — these route to the running
  daemon (serialized, rule-checked, retries on conflict). Do NOT use `tern
  set`, which appends the log directly and races. For creating whole new threads,
  `tern capture "<title>"` (fact-first) or file-edit + `import` is fine
  (distinct files don't collide); for field changes on existing threads under
  concurrency, prefer `tell`.
- Reads are instant off the warm coordinator (`tern up`): ready / blocked /
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
   handoff; the next session reads `tern show <id>`, not a file.
3. **Agent briefs are thread refs.** When spawning an agent for thread work,
   the brief is "read `tern show <id>`, write `progress` back" plus only the
   delta the thread doesn't hold — not a restatement of everything you know.
4. **Findings about the substrate go IN the substrate.** Found a bug mid-work?
   `capture` it, keep moving. Discovery-by-inhabiting is the point.
