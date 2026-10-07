# Failure modes seen in Smashcraft

Symptom, cause, rule. Smashcraft, 6-7 Oct 2026.

- "no element 1 in a table of 1" every tick at stage select: presentation built
  for one selection (stage decks drawn at shell start) outlived it. Key
  persistent presentation by the selection it was built for; headless journeys
  step through stage and fighter selection with computer slots
  (smashcraft:ts/test/bot-selection.test.ts).
- Bun and Lua tapes diverge (stray element, electric): a scratch object reused
  across hits/throws leaked fields; Bun runs all tapes in one process, Lua one
  process per tape. Reset every field of a reused scratch object; tapes catch it
  only when run in sequence.
- Every lane's Lua suite breaks on a literal like 0.02 or 1.4: not binary32 per
  the emitted-Lua number check. Wrap non-integer literals in `f32(...)` in tests too.
- 100+ MB Lua allocation spikes: per-kit text rebuilt by string concatenation in
  every checksum. Precompute static digests at load; no per-frame string building.
- Desync hunt ran 3.5 hours of one-variable native experiments (#158): nobody
  looked inside the engine. Read the autopsy line, then `wisp engine`.
- Green HUD, invisible stage, "menus could not load": `-loadfile` raced the
  post-login ladder-map scan. Host via the menu socket after the scan; treat any
  "model creation failed - war3mapImported" as a failed load.
- Private test client at the wrong aspect, pointer clamps: main-display play
  sharing its prefix rewrote War3Preferences on exit. One prefix per display
  role, or save/restore War3Preferences (wisp:docs/display-settings.md).
- Missing log line read as a state (no LoginDoorClose): War3Log is written in
  bursts. The menu socket outranks the log for sign-in and menus.
- Grey sky for seconds in the first match after a cold start: models draw late.
  Preload stage/scene models; take evidence frames only after a receipt says
  the scene is drawn.
- Missed clicks, wrong pointer targets, slow OCR: XTEST clicks shorter than one
  frame are missed by per-frame-sampled UI. Drive with in-map commands and
  receipts plus the menu socket.
- Receipt wait times out on a fresh game: it rewrote an identical receipt file.
  Wait on a counter or timestamp, never text equality.
- `bun wisp play` broke for every lane ("extract war3mapImported\\...Clip47
  failed", "Cannot open map archive"): ~20 lanes hand-edited one global input
  pointer, and concurrent builders shared an output folder, a `.next` file and
  a build worktree. Content-address shared inputs and name them per revision in
  Git; build into private staging, publish by one rename under a per-key lock.
