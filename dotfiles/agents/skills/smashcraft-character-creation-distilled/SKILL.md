---
name: smashcraft-character-creation-distilled
description: >-
  Create or complete Smashcraft playable fighters, including movesets, Blender
  animations, combat volumes, controls, selection UI, and deterministic replay.
  Use when adding a fighter or completing character-specific moves or animation
  coverage; not for unrelated Warcraft maps or general netcode work.
---

# Smashcraft character creation

Use the current Smashcraft goal and character brief as the design authority.
Inspect the actual Wurst checkout and its animation pipeline before extending
them. Apply wurst-development-distilled for source/toolchain work. A model
import or an attack clip alone does not make a playable character.

## Establish coverage, then build the fighter

Keep a compact character checklist in the existing project documentation with
missing, implemented, and native-verified states. Reuse existing move and asset
tables; do not create a second set of combat constants in prose. Identify
intentional exceptions explicitly rather than silently omitting an action.

| Family | Required actions and animation coverage |
| --- | --- |
| Ground attacks | Standing jab and any designed follow-ups; forward tilt with up/down angles, up tilt, down tilt; forward/up/down smashes with charge/release; dash attack |
| Aerial attacks | Neutral, forward, back, up, and down air; startup, active, recovery, and landing transitions |
| Specials | Neutral-, side-, up-, and down-special; grounded and airborne behavior, startup/active/recovery, cancellations, movement and landing rules |
| Grabs and throws | Standing grab, dash/pivot variants where supported, shield grab, whiff, hold, pummel, escape/release, forward/back/up/down throws; coordinated attacker and victim poses |
| Movement | Idle, walk, initial dash, run, turnaround, stop, crouch, jump squat, short/full jump, double jump, ascent/fall, fast-fall, normal and special landing |
| Defense | Shield raise/hold/release and shield hit/break; stunned/dizzy loop and recovery after shield break; spot dodge, both rolls, air dodge and wavedash landing |
| Recovery and damage | Directional hit reactions, hitlag, tumble, missed tech/prone, neutral/directional techs, get-up stand/attack/both rolls, ledge catch/hang/climb/jump/roll/attack, KO and respawn |
| Character entities | Projectiles, summons, traps, wings/forms and attachments: spawn, active action, contact, expiry, and interruption |

Shared systems may supply behavior and clips where they suit the fighter.
Character-specific exceptions come from the design, not from whichever stock
animation happens to exist. Unimplemented shared actions remain visible gaps;
do not claim them complete because the checklist mentions them.

## Make timing and contact explicit

For each move, define startup, active windows, recovery, cancellable windows,
ground/air eligibility, landing lag, invulnerability/intangibility, and any
resource or cooldown. Define damage, launch angle, knockback, hitlag, hitstun,
shield interaction, and contact/re-hit rules. Mark provisional tuning as such.
Use factual Melee reference data where relevant under external-code-distilled;
do not copy or translate unlicensed decompiled implementation.

Author/bake hitboxes and hurtboxes per action frame, including facing, weapon
reach, strong/weak phases, sweet spots/tippers, and per-target re-hit windows.
Animation informs authored volumes; local rendered bones and effect positions
never determine combat. Test simultaneous contacts through the shared rules.

Use the current shared dodge timings unless the owner changes them: spot dodge
22 total/protection 2–15; rolls 31/protection 4–19; air dodge 49/protection 4–29,
special landing lag 10. Keep frame numbering explicit when mapping to code.

## Author readable assets

Keep editable Blender sources and use the existing export pipeline. Check poses
from the actual side-view camera, both facings, and at gameplay size. Humanoid
neutral air defaults to the requested extended-leg kick unless specified
otherwise. Weapons stay attached and visible; clothing must not conceal the
active limb. Grounded knockdown poses must lie on the stage surface.

Preserve authored interpolation and existing clips when adding sequences.
Map each clip to the move's logical frames. Confirm correct startup, contact,
recovery, hitlag hold, and interruption transitions in Warcraft. A gray offline
render cannot prove native materials, attachment behavior, or animation phase
restoration. Add character-specific VFX/audio with stable semantic event IDs
so replay does not duplicate impacts, shots, or summon effects.

Every fighter must explicitly pass these damage-presentation checks:

- **Hitstun:** authored, readable "I've been hit" reactions for grounded and
  airborne hits, including launch/tumble where appropriate; transition back
  to controllable movement or into landing/knockdown according to simulation.
  An idle pose, attack pose, or generic frozen unit is not a hitstun animation.
- **Hitlag:** hold the correct contact pose for the exact simulation hitlag
  frames, then resume at the correct phase without restarting the clip. This
  is pose freezing, not a separately advancing animation. Check attacker and
  victim independently: do not assume the victim retains its pre-hit attack
  pose instead of entering a damage pose. Confirm transition ordering against
  the local reference before claiming Melee parity. Shield contact must hold
  the appropriate shield reaction. Test repeated hits and replay restoration;
  freezing animation must not stop global input sampling or the match clock.
- **Stunned/dizzy:** require a dedicated seamless loop for the incapacitated
  state after shield break, distinct from hitstun and hitlag. Use a tilted head
  and circular upper-body sway, adapted to the fighter's anatomy and readable
  from both facings. Pair it with small, brief, firework-like starbursts that
  appear intermittently around the head. Keep sparkles in the shared effect
  system and derive their apparently random timing/placement from replayable
  state; restoration must neither duplicate bursts nor advance them independently
  of the stun. Verify entry, looping, pause/hitlag, interruption, recovery and
  backward restoration in Warcraft. Stock loss and rematch must clear the effect.

## Connect a complete character

Use normalized, rebindable input actions; do not hardcode physical keys into
move logic. Ground jab/tilts/smashes and aerial direction selection are distinct.
Respect attack buffering through jump squat, facing-relative back air, shield
grab, and the designed special cancellation rules. C-stick down-air does not
press movement Down or force fast-fall; diagonal Down does not fast-fall.

Integrate roster selection, draggable chips, mirror matchups, rematch retention,
name, portraits, HUD and off-screen representation. Normalize portrait framing
while keeping weapons legible and retaining the intended team colors.

Keep all outcome-changing state in the pure Wurst simulation and snapshots:
action phases, input buffers, charge, grabs/throws, resources, forms, projectiles,
summons, traps, stable IDs and hit registries. Reset it correctly on stock loss
and rematch. Native handles, visual queries and audio remain outside replay.
Character additions must not weaken the agreed netcode isolation or claim
multiplayer safety from headless tests alone.

## Deliver through the real controls

Run the nearest focused Wurst checks for move timing/contact, interruptions,
ground/air transitions, buffer/cancel behavior and snapshot/replay equality.
Then build/install and exercise the fighter through actual controls in Warcraft,
including both facings and a mirror match. Inspect animation, attachments,
contact readability, UI and stock/rematch reset. Report source-tested,
installed, and observed-running behavior separately. A missing animation,
unwired move, or untested native interaction remains unfinished work.
