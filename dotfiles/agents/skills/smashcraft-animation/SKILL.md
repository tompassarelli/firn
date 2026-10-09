---
name: smashcraft-animation
description: >-
  Author and improve Smashcraft fighter animation: readable silhouettes,
  drills, locomotion, rolls, get-up attacks, paired grabs and throws, and
  nine-way damage reactions. Use for animation quality and action coverage.
---

# Smashcraft animation

Use `warcraft-modding` for the Wisp workflow and
`smashcraft-character-creation` for combat decisions. Read smashcraft:AGENTS.md
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
`references/library.md`.

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

## Make the change and ship

1. Author in private output with the existing generator for the family
   (`references/tools.md`). Materialize model-input symlinks before changing
   them and keep old sequence indices.
2. Before landing an authored attack, run `bun wisp anim score --fighter F
   --assets PRIVATE_ASSETS` from smashcraft:ts/ for Classic and again with
   `--graphics definitive`. Every changed move needs a passing row on all
   five lines, including a fresh independent judge's five scores at least
   4/5; the author cannot judge their own work. Prepare and record the judge
   with `bun wisp anim judge prepare` and `anim judge record`, following
   smashcraft:docs/animation-scorecard.md. Keep a change only if its score
   rises and no other line falls (#355); an unjudged or missing row cannot
   pass. Add missing move coverage to the sampler before using it to claim
   that move passes. For movement/recovery, `bun wisp view motion --assets
   PRIVATE_ASSETS` flags dead poses. Look at the changed action once in the
   game at gameplay zoom, both facings.
3. Publish art with `bun wisp inputs add FAMILY DIR`, regenerate asset
   metadata with the existing tool, and `safe-push --to main`. Never edit
   generated asset modules or a live input family in place.

## References

| File | Read when |
|---|---|
| `references/library.md` | picking a reference example or checking a factual claim about Sakurai's sources |
| `references/tools.md` | running the motion report or a drill, grab, pad or damage clip generator |
| `references/review-and-release.md` | changing balance, publishing a release, or recording a roster-wide review |
