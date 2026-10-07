# Animation tool commands

## Motion report and recovery clips

From smashcraft:ts/, `bun wisp view motion --assets PRIVATE_ASSETS` samples
production pose selection and reports 260 locomotion/recovery rows across the
13 fighters, plus stride cadence (about 4.8 s in the measured #171 run).
The durable report is smashcraft:docs/fighter-motion.md. Body, extremity and
directional travel expose dead poses; the rendered silhouette decides quality.

From the root, smashcraft:tools/animations/recovery-clips.ts and
smashcraft:tools/animations/recovery-model.ts append original recovery motion
without changing old sequence indices. Their current checks include distinct
recovery sequences, body travel >=5, extremity/directional travel >=20, and
get-up-attack travel >=30 in each direction. These are existing recovery
gates, not universal aesthetic thresholds. Use the nearest attack/reach check
for drills and throws; do not invent a second animation engine.

## Clip generators

From the Smashcraft root:

- `bun tools/animations/drill-clips.ts PRIVATE_ASSETS PRIVATE_OUTPUT` appends
  Blademaster, Warden and Shadow Hunter down-air motion with coordinated body
  and leading-limb rotation, preserving old sequence indices and writing
  private both-facing phase silhouette sheets. See
  smashcraft:docs/fighter-animation-work.md, "Hero drill clips". A cape can
  obscure the leading foot even when the motion check passes; judge the drawn
  silhouette and send the stable candidate to the native owner.
- `bun tools/animations/grab-clips.ts PRIVATE_ASSETS PRIVATE_OUTPUT [--character ID]` appends
  thirteen paired grab-family gestures for each of ten expansion heroes
  (130 clips), preserving existing indices. Authored contact times align
  holder and victim to the holder's actual contact frame despite different
  kit durations or hitstop. See smashcraft:docs/fighter-animation-work.md,
  "Paired expansion-hero grabs"; the original three fighters retain their
  existing grab authoring. Holds are deliberately still. Check unlike-height
  and mirror pairs in both facings through the native owner.
  Existing paired clips are reauthored at their same sequence indices and
  intervals. `--character ID` limits replacements to that expansion fighter;
  publish only changed input families and refresh the clip pool afterward.
- `bun tools/animations/grab-pads.ts` generates 80 mirror scripts in
  smashcraft:ts/test/native/pads/180/: ten expansion heroes, four throws and
  both holder facings. The production-simulation pass requires ordinary
  approach/catch/pummel and the requested release, then positions captures at
  contact and completion. Run that directory as one native pad batch with
  headless references alongside it; matching traces establish input/selection,
  while gameplay-zoom captures establish readability. Unlike-height pairs are
  an additional visual sample. See smashcraft:docs/fighter-animation-work.md,
  "Paired expansion-hero grabs" (Smashcraft commit b059af3a).
- `bun tools/animations/damage-clips.ts PRIVATE_ASSETS PRIVATE_OUTPUT`
  appends the 117 articulated pain clips and checks their drawn first poses.
  For the unresolved native interpolation seam,
  `bun tools/animations/damage-blend-probe.ts PRIVATE_ASSETS PRIVATE_OUTPUT`
  creates Archer probe models, each containing donor motion and a constant
  pain target, with checked hashed metadata. The `damage-blend-probe` map profile
  compares time scale zero and one in both facings. Follow
  smashcraft:docs/fighter-animation-work.md, "Native pain blending diagnostic";
  it separates pose blending from match clocks. Generator/build success alone
  does not establish native blending; the native owner inspects the comparison.

## Publishing art

Author in private output, materialize model-input symlinks before mutation,
preserve old sequences and run the focused geometry/motion check. Publish art
through `bun wisp inputs add FAMILY DIR` and the revision's immutable
smashcraft:build-inputs.json; regenerate asset metadata with the existing tool.
Never edit generated asset modules or a live input family in place.
