# Pad batches, pose captures and keyboard timing

- Run compatible pad parity scripts as one batch per pair, or shard one
  immutable candidate's batch across explicitly selected pairs:
  `bun wisp pad SCRIPT|DIR... --helper H --out DIR --map MAP.w3x
  --pair K...` (clients per the skill's "Native testing" section). It starts
  one game per pair, types `-dev reset` between scripts (it restores the
  boot match state; smashcraft:ts/test/dev-reset.test.ts holds the next
  match's checksums and moments equal to a new game's), starts every
  headless reference at once (`--headless-jobs N`) and compares as each
  native run ends. Measured on A+B, 7 Oct 2026, the old loop per script:
  new game 42-64 s, native run 23.5-26 s, headless compare 22 s (about
  1 min 50 s; 17 scripts over 35 min). The batch drops the new game and
  overlaps the compare: about 25 s a script per pair plus one new game, a
  reset costing about a second. Real-time runs slip on a saturated host
  (the batch reruns slipped scripts); run it on a quiet host
  (smashcraft:docs/native-bot-session.md, "Many scripts in one game").
- Exact pad pose captures use the original authored `capture` frames. With a
  scripted quick match, Smashcraft holds each pose locally through Wisp's
  framebuffer read while simulation and helper inputs continue unchanged
  (smashcraft:docs/native-bot-session.md). Both drawn receipts must name the
  requested match and frame; a skipped frame, absent completion or stalled clock
  makes the run INVALID, retaining earlier successful images. Wisp bounds a
  framebuffer read to eight seconds and reaps its capture child before returning
  failure (wisp:docs/player-view.md). `held visual` captures establish the pose;
  input-to-screen timing requires the live response route below.
- Keyboard response capture: `bun wisp map build --profile native-input --name NAME --out IMMUTABLE_MAP.w3x`
  retains the playable keyboard path, two-frame delay, rollback and predicted
  pooled fighters, adding developer setup and the response probe (Smashcraft
  commit 019983c0). Ctrl+G starts recording and Ctrl+H exports callback/input
  rows to CustomMapData; the magenta marker identifies the callback drawn in
  captured pixels. Pair original host input timestamps with framebuffer
  timestamps: exported game-clock rows alone do not measure press-to-screen
  latency. Report diagnostic overhead separately; journal integrity uses a
  different input path. See smashcraft:docs/native-bot-session.md,
  "Raw playable cost captures".
