---
name: smashcraft-character-creation
description: >-
  Design, build and test a Smashcraft fighter or move: role and trade-offs,
  move phases, hit regions and hurt capsules, damage, knockback, shield,
  recovery, rollback state, presentation and selection. Use for a new fighter
  or a move change, not for other Warcraft maps.
grounded: 2026-10-09
written: 2026-10-09
metadata:
  kind: domain
---

# Smashcraft character creation

- Read smashcraft:AGENTS.md and smashcraft:docs/typescript.md before editing smashcraft:ts/.
- Use `warcraft-modding` for Wisp and `smashcraft-animation` for animation quality.
- Start from `origin/main` in a worktree with `bun install --frozen-lockfile` in ts/.
- Query source or move data for tuning numbers.
- Keep the fighter's coverage checklist in its issue until Tom can select it and play its moves.
- Follow smashcraft:docs/gameplay-design.md and smashcraft:docs/delivery-goal.md.
- Author original regions and capsules while citing Melee rows only for factual timing or trade-off relations under `external-code`.
- Diversify moves through hitboxes, startup, recovery and rewards without stale moves, freshness bonuses or L-cancel.
- Apply automatic half-authored landing lag to every aerial in sim/moves.ts.
- Prevent grabs, throws and starters from trapping victims in input-insensitive loops.
- Name guaranteed strings and checked victim inputs until the escape detector lands.
- Trade greater shield damage for later recovery or earlier defender response under docs/move-comparisons.md.
- Keep windows within Tom's accepted gameplay-design.md bounds.
- State how the fighter launches into follow-ups such as tech chases.
- Apply docs/design/balance.md: 40–60% wins, top-move spam wins at most 45%, and no move above 40% damage except a named signature.
- Record explosive openings per kill and archetype, aerial, approach, ranged and special shares in each fighter's design doc.
- Give new fighters a play-style profile and cite before/after tuning scores from `bun wisp farm balance --wait`.
- Brief a fighter's role, measurable strengths/weaknesses and differences from every existing fighter before implementation.
- Brief each move's decision for both players, reward, startup, active, recovery, landing, shield outcome and spacing risk with original values marked provisional.
- Author startup, active/recovery/cancel/contact windows, eligibility, landing lag, intangibility, resources, cooldowns, damage, launch vector/base/growth, hitlag and shield behavior.
- Allow one hit per target per attack in each positive contact window.
- Treat frame 0 as the start tick and startup N as first active frame N, displayed N+1.
- Preserve shared per-action timing except `characterAttackActiveFrames`, justifying any new per-fighter startup/total path.
- Match the whole-duration attack clip to timing changes.
- Resolve contact from authored volumes rather than rendered bones or effects and test simultaneous contacts/trades through the shared resolver.
- Use sim/conditions.ts's shared dodge profile unless Tom changes it.
- Spend the aerial jump and enter helpless fall on up-special while retaining one aerial jump after walking off a ledge.
- State recovery reach, ledge options and edge-guard weakness and implement computer recovery in match/botRecovery.ts.
- Generate fighterAssetInfo.ts through tools/animations/build-assets.sh and package.ts from tools/animations/ Blender clips.
- Keep proprietary models under ~/.local/share/smashcraft-build-inputs/ under `repo-safety`.
- Register new model families in ts/scripts/wisp/mapInputs.ts and expectations in ts/scripts/wisp/playerView.ts.
- Check gameplay-size side-view poses in both facings for attached weapons, visible active limbs, stage-grounded knockdowns and readable ground/air reactions.
- Hold attacker and victim contact poses for their exact simulated hitlag without pausing input or match time.
- Present shield break as a seamless dizzy loop with shared starbursts cleared on stock loss/rematch.
- Give effects and sounds stable event IDs to prevent replay duplicates.
- Use normalized rebindable actions with distinct jab/tilt/smash/aerial directions, jump-squat buffering, facing-relative back air, shield grab and designed special cancels.
- Keep C-stick down-air independent of Down input and fast-fall.
- Snapshot/reset every outcome-changing phase, buffer, charge, grab, resource, projectile, summon, stable ID and hit registry on stock loss/rematch.
- Keep native handles, visuals and audio outside replay.
- Supply roster chip, portrait, name, HUD plate, mirror match, rematch and off-screen indicator with text in the game's language.
- Assign a campaign-appropriate home stage, using native assets first, with a one-line lore reason in ts/src/game/menu/homeStages.ts and docs/design/home-stages.md.
- Satisfy ts/test/home-stages.test.ts for every selectable fighter, allowing shared stages.
- Edit with `bun wisp dev` and demonstrate the rule's contract test fails without the change using sim/normals.tests.ts's pattern.
- Compare `bun wisp interactions --move FIGHTER:MOVE` before/after and record changes in the commit message.
- Refresh move-data snapshots when frame data or regions change through [tools.md](references/tools.md).
- Run `bun run check`, `bun run test` and play both facings through `bun wisp hot` or `bun wisp lan fresh MAP`.
- Land with `safe-push --to main` and fix forward if CI's Lua, parity or perf suites fail.
- Read [source-map.md](references/source-map.md) when locating fighter implementation files.
- Read [moveset.md](references/moveset.md) when listing required actions.
- Read [design-reading-list.md](references/design-reading-list.md) for fighting-game, Melee or interaction-graph design questions.
- Read [balance-and-release.md](references/balance-and-release.md) for balance changes or release gates.
