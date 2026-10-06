---
name: smashcraft-character-creation
description: >-
  Take a Smashcraft fighter or move from concept to a playable, tested build:
  role and trade-offs, models and animations, move phases and buffering,
  per-frame hit regions and hurt capsules, damage, knockback and shield,
  recovery, rollback state, presentation, selection and packaging, and the
  headless and native checks. Use for a new fighter or a bounded move or
  character change; not for unrelated Warcraft maps or general netcode work.
---

# Smashcraft character creation

Smashcraft is TypeScript on Wisp (smashcraft:ts/). Before code, read
smashcraft:AGENTS.md, apply warcraft-modding, and
read smashcraft:docs/typescript.md. Work in an owned lane from `origin/main`
(`bun install --frozen-lockfile` in ts/). Take every number from the source
or generated data linked here; this skill holds no tuning values.

Name the fighter or move sample and the intended player-facing outcome before
work starts, and keep the coverage checklist and Status in the fighter's
issue, never in a doc. A model import, an attack clip or a passing test alone
does not make a playable fighter.

## Read the design layers in order

Each layer is descriptive and sourced; the stance lives only in the last.

1. Fighting-game language: smashcraft:docs/design/fighting-games.md (#64).
2. Platform-fighter language: smashcraft:docs/design/platform-fighters.md (#64).
3. Melee case study: smashcraft:docs/design/melee/ (#65), built on the
   physics facts in smashcraft:docs/smash-melee-reference/ and the one
   frame-data corpus, smashcraft:references/melee-frame-data/records.jsonl.
4. Modern mechanics: smashcraft:docs/design/modern-platform-fighters.md (#66).
5. Measurement: smashcraft:docs/design/interaction-graph.md and
   `bun wisp interactions` (#67); smashcraft:docs/design/execution-windows.md (#69).
6. Tom's stance, the only place for owner decisions:
   smashcraft:docs/gameplay-design.md, with its deviations from Melee and
   open questions. smashcraft:docs/delivery-goal.md lists each current fighter's
   required moves and approved custom mechanics.

#62 owns combat geometry, hurtboxes that follow animation, trade-offs as
numbers and the model of fun; link its results rather than restating them.

## Check every design against the owner decisions

- **Original hitboxes.** Melee data is a reference, not a template. Author
  each fighter's regions and capsules; cite a Melee row only as evidence for
  a relation (timing, a trade-off between fighters), and say so.
- **Diversity by construction.** Moves differ through their hitboxes,
  startup, recovery and rewards. No stale moves or freshness bonus, no
  L-cancel: every aerial lands with half its authored landing lag
  automatically (smashcraft:ts/src/game/sim/moves.ts). No execution test
  without an opponent.
- **No false agency.** A new fighter's grabs, throws and combo starters must
  pass the zero-agency detector (#68, in progress): no stretch where the
  victim's input changes nothing and loops without escape. Until it lands,
  name each guaranteed string and the victim inputs you checked.
- **Interaction graph.** Read smashcraft:docs/design/interaction-graph.md,
  then evaluate every new or changed move with
  `bun wisp interactions --move FIGHTER:MOVE` (from ts/, for example
  `rifleman:down-tilt`): it plays the fighter's shield, landing, ledge, tech,
  out-of-shield and neutral situations and prints every place the move
  appears, its frame advantage and punishes, and what changed in the graph.
  Keep the move-comparison rule that greater shield damage must cost later
  recovery or an earlier defender response (smashcraft:docs/move-comparisons.md).
- **Windows.** Any required window stays inside the bounds Tom has accepted
  in gameplay-design.md; proposals are in execution-windows.md.
- **Direction, not yet a rule:** fighters generally need launchers into
  follow-ups such as tech chases. State how the fighter starts one.

## Write the brief first

For a fighter: intended role, strengths and vulnerabilities as numbers to
check (frame data, reach, mobility, weight, recovery), and how it differs from
each current fighter. For a move: the decision it creates for both players,
its reward and its risk (startup, active, recovery, landing, shield outcome,
spacing). Separate reference facts, deliberate departures and hypotheses.
Mark original values provisional. Query current facts instead of guessing,
from the repository root:

```sh
jq 'select(.kind == "contact" and .character == 1 and .move == "down-tilt")' tools/move-data/moves.jsonl
```

Character IDs, move names and row kinds are in smashcraft:docs/move-data.md;
bot-soak balance data in smashcraft:evidence/soak-*; trade-off method in
smashcraft:docs/move-reference-join.md.

## Where each part lives

| Concern | Owning source (smashcraft:ts/src/game/ unless noted) | Reference |
| --- | --- | --- |
| Identity, action and special codes | sim/codes.ts: append only, numbers are checksum-canonical | |
| Movement and physics parameters | sim/tuning.ts; live tunables in ts/scripts/wisp/tunables.ts | docs/physics.md |
| Move phases | sim/moves.ts: per-action startup, active, total; per-fighter active via `characterAttackActiveFrames` | docs/physics.md "Prototype attack phases" |
| Hit regions per frame | sim/hitRegions.ts `activeRegion`: per fighter, action and attack frame; lower index wins; windows gate re-hits | docs/physics.md "Frame-authored hit regions" |
| Contact geometry, hurtboxes | physics/contactGeometry.ts: strike capsule per action, pose-independent hurt capsule per fighter; animated hurtboxes are #62 | docs/move-data.md |
| Damage, knockback, hitlag, hitstun, DI | sim/knockback.ts, sim/contacts.ts, sim/hits.ts | docs/melee-hitlag-scalars.md, melee-hitstun-boundaries.md |
| Shield, dodges, grabs | sim/shield.ts, sim/conditions.ts (dodge profile), sim/grabs.ts | docs/melee-analog-shield.md, docs/delivery-goal.md |
| Specials, projectiles, summons | sim/specials.ts, sim/projectiles.ts, sim/summons.ts | docs/physics.md |
| Recovery and ledge | up-special helpless fall in sim/specials.ts; sim/ledge.ts | docs/physics.md "Up-special aerial recovery", "Outer ledge recovery" |
| Input selection and buffering | input/combat.ts (stick, C-stick, walk to action), input/attackBuffer.ts, sim/roster.ts `Controls` | docs/player-guide.md |
| Rollback state | sim/fighter.ts (every mutable field), replay/fighterState.ts, replay/canonical.ts | docs/netcode-proposal.md |
| Computer opponent | match/botMoves.ts reads authored regions; specials and recovery are per fighter | gameplay-design.md "Computer opponent" |
| Clips and poses | presentation/fighterClips.ts, fighterPose.ts, damagePose.ts; generated fighterAssetInfo.ts | docs/fighter-animation-work.md |
| Effects and sounds | presentation/impactEvents.ts, specialEffectState.ts, render/; assets/modelSoundInfo.ts | docs/player-view.md |
| Selection, HUD, packaging | ui/selectionUi.ts, ui/matchHud.ts, objectData.ts, ts/scripts/wisp/mapInputs.ts | docs/typescript.md "Build the map" |
| Measurement registries | ts/scripts/moveData.ts, ts/test/soak/game.ts, ts/scripts/soakOutcomes.ts, ts/scripts/wisp/soak.ts, ts/scripts/meleeOracle.ts, ts/scripts/wisp/playerView.ts | |

A new fighter touches every row. `grep -rln "Character.demonHunter\|illidan" ts/src ts/scripts ts/test`
lists the seams the last fighter needed; a move change usually touches only
moves.ts or hitRegions.ts, a contract test and the move data.

## Cover the whole moveset

| Family | Required actions and animation coverage |
| --- | --- |
| Ground attacks | Jab and designed follow-ups; forward tilt with up/down angles, up tilt, down tilt; forward/up/down smashes with charge and release; dash attack |
| Aerials | Neutral, forward, back, up, down: startup, active, recovery, landing |
| Specials | Neutral, side, up, down; grounded and airborne forms, cancels, movement and landing rules |
| Grabs and throws | Standing, dash and shield grab, whiff, hold, pummel, escape, four throws; coordinated holder and victim poses |
| Movement | Idle, walk, dash, run, turnaround, stop, crouch, jump squat, short/full/double jump, fall, fast-fall, landings |
| Defense | Shield raise/hold/release, shield hit and break, dizzy loop and recovery; spot dodge, rolls, air dodge, wavedash landing |
| Recovery and damage | Directional hit reactions, hitlag, tumble, missed tech, techs, get-up options, ledge catch/hang/climb/jump/roll/attack, KO, respawn |
| Character entities | Projectiles, summons, traps, forms, attachments: spawn, action, contact, expiry, interruption |

Shared systems supply behavior and clips where they suit the fighter;
exceptions come from the design. An unimplemented action stays an open box.

## Timing, contact and defense

- Per move, author startup, active windows, recovery, cancel windows,
  ground/air eligibility, authored landing lag, intangibility, resources and
  cooldowns; then damage, launch vector, growth and base, hitlag and shield
  behavior, and contact windows (each positive window allows one hit per
  target per attack). Frame 0 is the start tick: startup N means first active
  attack frame N, display frame N+1.
- Timing is per action, shared by every fighter, except active frames
  (`characterAttackActiveFrames`). A per-fighter startup or total needs a new
  seam; justify it. The clip plays over the attack's whole duration, so a
  timing change needs a matching clip; a damage, launch or region change does not.
- Animation informs authored volumes; rendered bones and effect positions
  never decide contact. Test simultaneous contacts and trades through the
  shared resolver.
- Use the shared dodge profile (smashcraft:docs/delivery-goal.md, source in
  sim/conditions.ts) unless Tom changes it.
- Recovery: an up-special spends the aerial jump budget and ends in helpless
  fall; leaving a ledge without jumping keeps one aerial jump. State the
  fighter's recovery reach, ledge options and edge-guard weakness in the
  brief, and make match/botRecovery.ts bring the computer back to the stage.
- Factual Melee data only under external-code rules; never copy or translate
  decompiled implementation.

## Models, animations and presentation

Blender scripts in smashcraft:tools/animations/ author clips (Python is the
Blender boundary); `tools/animations/build-assets.sh` writes
smashcraft:build/animation-assets/ and `package.ts` regenerates
fighterAssetInfo.ts. Never edit generated modules. Proprietary models and base
maps stay under ~/.local/share/smashcraft-build-inputs/ (repo-safety).
A map build's `--assets` directory holds the generated asset families listed
in smashcraft:ts/scripts/wisp/mapInputs.ts; a new model also needs an
expectation in ts/scripts/wisp/playerView.ts or the scene check fails.

Check poses from the side-view camera, both facings, at gameplay size.
Weapons stay attached and visible; clothing does not hide the active limb;
knockdown poses lie on the stage. Give character effects and sounds stable
semantic event IDs so replay never duplicates them. Every fighter passes:

- **Hitstun:** readable grounded and airborne hit reactions, tumble where
  appropriate, returning to control or landing as the simulation says.
- **Hitlag:** hold the contact pose for exactly the simulation's hitlag, then
  resume at the right phase, attacker and victim checked separately, shield
  contact included; freezing never stops input sampling or the match clock.
- **Dizzy:** a dedicated seamless shield-break loop with intermittent
  starbursts from the shared effect system, timed from replayable state;
  stock loss and rematch clear it.

## Controls, state and selection

Use normalized, rebindable actions; never hardcode keys in move logic. Keep
jab, tilts, smashes and aerial direction selection distinct; respect attack
buffering through jump squat, facing-relative back air, shield grab and the
designed special cancels. C-stick down-air neither presses Down nor
fast-falls.

Keep every outcome-changing value in the simulation and its snapshots:
phases, buffers, charge, grabs, resources, forms, projectiles, summons,
traps, stable IDs and hit registries, reset on stock loss and rematch. Native
handles, visual queries and audio stay outside replay.

Selection: roster chip, portrait, name, HUD plate, mirror match, rematch
retention, off-screen indicator. Player-facing names and text stay in the
game's language.

## Route a change to a playable build

From smashcraft:ts/ unless noted. Through the machine-capacity helper
(machine-capacity):
`bun run test`, the Lua32 suite, tapes, soaks, CI and map builds.

1. **Baseline.** Before editing, record the soak you will compare against:
   `SOAK_OUTCOMES=FILE bun wisp soak --policy cpu --matches 540 --seed 2 --minutes 20`.
   Computer-vs-computer matches are deterministic; fuzz matches vary slightly
   between runs of the same code, so read them as noise of a few matches.
2. **Edit with `bun wisp dev` running.** Add a contract test beside the
   rules it pins (pattern: the per-fighter down-air and down-tilt tests in
   sim/normals.tests.ts) and see it fail without the change. Focused:
   `GAME_TESTS=sim/normals bun test test/game.test.ts -t NAME`; `bun run check`.
3. **Interaction graph.** The graph is not committed; each checkout writes its
   own. Before the change, write it with `bun wisp interactions`. After it,
   `bun wisp interactions --move FIGHTER:MOVE` (about 10 s, capacity scope)
   compares against that graph: read where the move wins, loses and punishes,
   and record what changed in the commit message. Never commit
   smashcraft:tools/move-data/interactions/.
4. **Move data.** From the repository root, in this order, because the
   reference join reads the checked-in snapshots:
   `tools/move-data/export.sh --check`, then `compare.sh --check` (it also
   runs `interactions --check`, which fails until step 3 rewrote the graph),
   then `reference.sh --check`. On a difference, diff
   smashcraft:build/move-*/ against smashcraft:tools/move-data/, confirm only
   intended rows changed, copy the generated file over the snapshot and
   check again. `bun run test` doesn't run these checks.
5. **Shared rules.** `bun wisp oracle` (0 mismatches; it checks shared rules
   and borrowed movement, not move damage). A new fighter declares the rows
   it borrows in ts/scripts/meleeOracle.ts. `bun wisp headless` plays the
   quick match in two simulated clients (`headless desync` is a detector
   self-test that must report a desync, not a gate).
6. **After soak and record.** Same soak command and seed;
   `bun scripts/soakOutcomes.ts FILE` summarizes each run. Put the raw
   files and a README in smashcraft:evidence/<topic>-<yyyymmdd>/, add a
   before/after section to smashcraft:docs/move-comparisons.md, and correct
   any doc sentence that states the old value.
7. **Publication gates.** Merge `origin/main` (and rerun
   `bun install --frozen-lockfile` when it changed ts/wisp.lock), then `bun run check`,
   `bun run test`, `LUA=<lua32> bun scripts/lua-tests.ts`,
   `LUA=<lua32> bun wisp tapes` and `LUA=<lua32> bun wisp parity numeric`
   (both also need a toward-zero Lua: `TOWARD_ZERO_LUA`, or built with nix
   on first use), `bun scripts/unused-code.ts`, `bun wisp oracle`,
   `CI_TIMING=report bun scripts/ci.ts`, then `safe-push --to main`.
8. **Map build.** Reuse the newest candidate's private inputs: the first
   line of ~/.local/share/smashcraft-build-inputs/playable-00NN/build*.log is
   its exact command (smashcraft:docs/playable-00NN.md can lag behind it):
   `bun wisp build --profile main|playable --base BASE.w3m --container CONTAINER.w3x --assets DIR --summon DIR --name NAME --out OUT.w3x`.
   A diagnostic build takes its own name and folder, never the next
   `Smashcraft 0.0.N`; only a release candidate takes that number.
9. **Native, by the native owner only.** Name the exact map and commands
   for them: `bun wisp fresh MAP.w3x` (development profile, `-dev quick`),
   `bun wisp hot --data A --data B --watch` for later saves,
   `bun wisp parity capture --bot ...` for a bot session
   (smashcraft:docs/native-bot-session.md), `bun wisp view scene DIR`.
   Check both facings and a mirror match, animation against the active
   frames, contact readability, UI, and stock and rematch reset.

Report source-tested, built and native-observed behavior separately. Soak
and frame data do not establish balance; Tom can veto any tuning.

## Keep claims bounded

Input timing claims cite #26's bounded historical result, the current
regression and acceptance in #60, and stall recovery in #48; never restate
them from a character change. Don't reopen viability research or add Wisp or
framework work without a concrete blocker; a Wisp change goes through its own
lane and `bun run update:wisp`.
