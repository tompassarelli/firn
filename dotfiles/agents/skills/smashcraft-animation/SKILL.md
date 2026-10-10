---
name: smashcraft-animation
description: >-
  Author and improve Smashcraft fighter animation: readable silhouettes,
  drills, locomotion, rolls, get-up attacks, paired grabs and throws, and
  nine-way damage reactions. Use for animation quality and action coverage.
grounded: 2026-10-09
written: 2026-10-09
---

# Smashcraft animation

Use `warcraft-modding` for the Wisp workflow and `smashcraft-character-creation`
for combat. Read smashcraft:AGENTS.md and smashcraft:docs/fighter-animation-work.md.
An animation repair never retunes combat timing or collision.

The deliverable is a readable fighter at gameplay side-view zoom, both facings.
A mapped clip, a rotating effect or a nonzero vertex delta does not prove the
action reads. Use original authored motion and licensed inputs, never imported
Nintendo animation or decompiled code. Private art stays under
`~/.local/share/smashcraft-animation-reference/` or the private build-input
store, outside Git.

## Author the action

Block three silhouettes: preparation, contact, recovery; read them with particles
hidden. Separate the active hand, foot or weapon from the torso; involve
shoulders, pelvis and weight. Heavy swings plant a support and follow through;
agile actions coil and spring. Fit phases to the existing simulation frames, keep
a fast move's speed, and add no anticipation frames for looks.

Judge at the smallest gameplay view, both facings, plus key intermediate poses.
Inspect the rendered mesh, not bone angles: large rotation can read static.

## Action families

- **Locomotion:** plant each support foot and match stride cadence to simulated
  travel; jump squat compresses before extension; landing separates rising,
  falling and impact. Floating fighters move body, cloth or weapon, not feet.
- **Drills and spins:** turn the visible body through the attack with a leading
  foot or blade and coordinated pelvis and shoulders; show preparation, sustained
  rotation and an intentional exit. Symmetric weapons and straight bodies hide
  rotation, so vary shoulder, knee and silhouette phases. An effect orbiting an
  unmoving body fails.
- **Rolls, dodges, techs, get-ups:** direction reads through local body motion,
  not stage translation: start low, tuck or rotate, recover support, keep feet on
  the floor. Get-up attacks strike every covered direction, then stand. Tell spot
  dodge, air dodge, missed tech, successful tech and ledge action apart; reuse
  existing recovery clips first.
- **Grabs and throws:** author holder and victim together: stable grip, localized
  pummel, distinct release in each of four directions, victim following through
  its own pose. Check unlike-height and mirror pairs in both facings. An unchanged
  hold with launch only fails.
- **Attacks and specials:** the active limb or weapon follows the strike direction
  at contact frames; each special has startup, action and recovery or landing;
  charge and release are different poses. Keep each fighter's own mechanics.

## Damage and shield feedback

Per fighter, author high, mid and low contact-height reactions at small, medium
and large intensity: nine distinguishable poses, classified from accepted contact
and authored intensity, not a bone query. High recoils the head and chest; mid
contracts or twists the torso; low loses lower-body support. Never use scalar tilts.

In hitstop, blend from the actual current pose into a readable pain silhouette,
never through idle. Timing is move-appropriate (Tom delegated it in #181; the
earlier 1–2 frames is guidance, not a gate). Hold through the stop, then continue
hitstun or tumble as the simulation says. Presentation never advances attack,
hitstun, input or collision clocks.

Hitstop shake is presentation only (horizontal on the ground, vertical in the air,
decaying, camera-compensated); collision stays put. Shield contact has its own
impact and defender reaction, not a damaging hit. Hitlag, released hitstun and
released shieldstun are distinct; body hue in them is unresolved, so capture
consecutive contact, stop and release frames before claiming a match.

## Make the change and ship

1. Author in private output with the family's generator (`references/tools.md`).
   Materialize model-input symlinks before changing them; keep old sequence
   indices.
2. Before landing an authored attack, run `bun wisp anim score --fighter F
   --assets PRIVATE_ASSETS` from smashcraft:ts/ for Classic, then with
   `--graphics definitive`. Each changed move needs a passing row on all five
   lines and a fresh independent judge's five scores at least 4/5; the author
   never judges their own work (`anim judge prepare` and `anim judge record`, per
   smashcraft:docs/animation-scorecard.md). Keep a change only if its score rises
   and no line falls (#355). Add missing move coverage to the sampler first. Flag
   dead poses in movement or recovery with `bun wisp view motion --assets
   PRIVATE_ASSETS`. Look once in game at gameplay zoom, both facings.
3. Publish art with `bun wisp inputs add FAMILY DIR`, regenerate asset metadata
   with the existing tool, then `safe-push --to main`. Never edit generated
   modules or a live input family in place.

## References

| File | Read when |
|---|---|
| `references/library.md` | picking a reference example or checking a factual claim about Sakurai's sources |
| `references/tools.md` | running the motion report or a drill, grab, pad or damage clip generator |
| `references/review-and-release.md` | changing balance, publishing a release, or recording a roster-wide review |
