# Where each part lives

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
