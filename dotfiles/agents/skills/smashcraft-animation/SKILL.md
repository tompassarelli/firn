---
name: smashcraft-animation
description: >-
  Author and improve Smashcraft fighter animation: readable combat silhouettes,
  drills, locomotion, rolls, get-up attacks, coordinated grabs and throws, and
  nine-way damage reactions. Use for animation quality and action coverage;
  Warcraft runtime work and combat design retain their owning skills.
---

# Smashcraft animation

Use warcraft-modding for the map/runtime boundary and
smashcraft-character-creation for combat decisions. Read smashcraft:AGENTS.md
and smashcraft:docs/fighter-animation-work.md. Keep the action timing and
collision rules; an animation repair is not permission to retune combat.

The deliverable is a readable fighter at the actual side-view gameplay camera,
in both facings. A mapped clip, rotating effect, or nonzero vertex measurement
alone does not establish that the action reads. Use original authored motion
and licensed Warcraft inputs, never imported Nintendo animation or copied
decompiled implementation. Private art, reference stills and recordings stay
under ~/.local/share/smashcraft-animation-reference/ or the established private
build-input store, outside every Git tree.

## Author the action, not just a moving model

Block three deliberate silhouettes: preparation, contact/action, recovery.
Read the gesture in silhouette with particles hidden before polishing it.
Separate the active hand, foot or weapon from the torso; involve shoulders,
pelvis and weight rather than wiggling one joint. A heavy swing uses a planted
support and visible follow-through; an agile action can coil and spring. Fit
these phases to the existing simulation frames. Preserve a fast move's speed;
do not add anticipation frames solely to improve the pose.

Judge the smallest normal gameplay view, both facings, and important
intermediate poses. Exaggerate the gesture enough to survive the camera,
weapon/clothing occlusion and short duration. Keep stable weapon attachment
and recognizable fighter proportions. Large rotation or vertex travel can
still read as a static silhouette: inspect the rendered mesh, not bone angles.
Sakurai's attack-stage and follow-through sources are indexed in
nixos-config:dotfiles/agents/skills/smashcraft-animation/references/library.md;
read that reference when selecting an example or checking a factual claim.

## Action families

- **Locomotion:** plant each support foot, transfer weight, alternate the
  stride and match its cadence to simulated travel. Turn and brake show
  directional intent; jump squat compresses before extension; airborne and
  landing poses distinguish rising, falling and impact. Floating fighters
  use body/cloth/weapon motion appropriate to their form rather than feet.
- **Drills and spins:** turn the fighter's visible body through the attack,
  with an extended leading foot or blade and coordinated pelvis/shoulders.
  A downward drill has a clear vertical axis and narrow leading silhouette;
  a horizontal spinning cut has a broad cutting arc. Show preparation,
  sustained rotation during active windows and an intentional exit/landing.
  Symmetric weapons and a straight body can hide rotation; vary shoulder,
  knee and silhouette phases. An effect orbiting an unmoving body fails.
- **Rolls, dodges, techs and get-ups:** roll/tech direction must read through
  local body motion, not stage translation alone. Start low, tuck/rotate,
  recover support; keep feet/body at the floor without sinking below it.
  Get-up attacks visibly strike every direction their active regions cover,
  then stand. Distinguish spot dodge, air dodge, missed tech, successful tech
  and ledge action. Use the existing authored recovery clips before adding
  another set.
- **Grabs and throws:** author holder and victim together. Reach into the
  grip, establish a stable hold, show a localized pummel and distinct release
  in each of four directions. The victim follows the hold/release through
  their own coordinated pose; avoid bodies or weapons occupying one silhouette.
  Check unlike-height pairs and a mirror pair, both facings. A hold is a held
  pose by design; a throw that is an unchanged hold with launch only fails.
- **Attacks and specials:** show the active limb/weapon following the authored
  strike direction at its contact frames. Each aerial and ground/air special
  needs deliberate startup, action and recovery/landing. Charge and release
  are different poses. Preserve characteristic body mechanics across the
  roster rather than assigning one generic gesture to every fighter.

## Damage and shield feedback

For each fighter, author high/mid/low contact-height reactions at
small/medium/large intensity: nine distinguishable pain poses. Classify from
accepted contact and its authored intensity relation, not an arbitrary
rendered bone query. High recoils head/upper chest; mid contracts/twists the
torso; low loses lower-body support. Scale the whole silhouette and limb
response across intensity while preserving height identity. Do not replace
the nine poses with nine scalar root tilts.

Blend from the **current interrupted pose** into a promptly readable pain
silhouette during hitstop. Tom delegated researched, move-appropriate timing
in #181; his earlier 1–2 frames is guidance, not a fixed gate. Capture the
actual current pose; never visit idle first. Hold the readable pain silhouette
during the remaining stop, then continue hitstun/tumble as the simulation says.
The historical Sakurai article uses four transition frames; neither that
number nor the earlier guidance is a claimed Melee constant. Presentation
interpolation must not advance attack, hitstun, input or collision clocks.

Hitstop vibration is presentation only. Sakurai describes horizontal shake
on the ground (avoid floor clipping), vertical in the air, decreasing amplitude
over the stop and compensation for camera distance. Keep collision stationary.
Shield contact has its own shell impact and defender reaction; it is not a
damaging-body hit. Hitlag, released hitstun and released shieldstun are
distinct intervals. Body hue in those intervals is an unresolved reference
measurement, not an established rule: capture consecutive contact/stop/release
frames before claiming a match. Do not infer tint timing from a single still.

## Use the existing fast authoring and checks

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

Author in private output, materialize model-input symlinks before mutation,
preserve old sequences and run the focused geometry/motion check. Publish art
through `bun wisp inputs add FAMILY DIR` and the revision's immutable
smashcraft:build-inputs.json; regenerate asset metadata with the existing tool.
Never edit generated asset modules or a live input family in place.

Record a roster-by-action review in the owning issue: all 13 fighters and the
movement, attacks/aerials/specials, defense/recovery, grab/throw and nine-damage
families. Distinguish mapped, motion-checked and native-observed. Map gaps to
the existing issues (#180 quality, #171 recovery, #181 pain, #156 original
fighter swings, #152 drills, #163 jabs, #82 effects) rather than creating a
ticket per pose. Declare the finite action sample before running it.

Send one stable candidate and batched action scripts to the native owner;
do not mutate another owner's clients. Existing recovery scripts are in
smashcraft:ts/test/native/pads/171/. Native evidence must show gameplay zoom,
both facings, contact/stop/release and action completion, with the simulation's
frame budget intact. Reuse passing evidence for unrelated merges. A completed
research skill can land independently while roster repairs continue.
