---
name: smashcraft-character-creation
description: >-
  Design, build and test a Smashcraft fighter or move: role and trade-offs,
  move phases, hit regions and hurt capsules, damage, knockback, shield,
  recovery, rollback state, presentation and selection. Use for a new fighter
  or a move change, not for other Warcraft maps.
---

# Smashcraft character creation

Smashcraft is a game written in TypeScript on Wisp (smashcraft:ts/). Before
code, read smashcraft:AGENTS.md and smashcraft:docs/typescript.md and use
`warcraft-modding` for the Wisp workflow. Work in a worktree from
`origin/main` (`bun install --frozen-lockfile` in ts/). Take every number from
the source or the move data; this skill holds no tuning values. Use
`smashcraft-animation` for animation quality.

Done means Tom can pick the fighter and play the move. A model import, an
attack clip or a passing test alone isn't a playable fighter. Keep the
fighter's coverage checklist in its issue, never in a doc.

## Design rules

Tom's stance is smashcraft:docs/gameplay-design.md;
smashcraft:docs/delivery-goal.md lists each fighter's required moves.

- **Original hitboxes.** Melee data is a reference, not a template. Author
  each fighter's regions and capsules; cite a Melee row only as evidence for
  a relation such as timing or a trade-off, and say so.
- **Diversity by construction.** Moves differ through hitboxes, startup,
  recovery and rewards. No stale moves, no freshness bonus, no L-cancel:
  every aerial lands with half its authored landing lag automatically
  (sim/moves.ts).
- **No false agency.** Grabs, throws and combo starters must not leave a
  stretch where the victim's input changes nothing and loops without escape
  (#68). Until the detector lands, name each guaranteed string and the victim
  inputs you checked.
- **Shield cost.** Greater shield damage must cost later recovery or an
  earlier defender response (smashcraft:docs/move-comparisons.md).
- **Windows** stay inside the bounds Tom accepted in gameplay-design.md.
- **Launchers.** Fighters generally need a launcher into follow-ups such as
  tech chases; say how this one starts one.

## Write the brief first

For a fighter: role, strengths and weaknesses as numbers to check (frame
data, reach, mobility, weight, recovery) and how it differs from each current
fighter. For a move: the decision it creates for both players, its reward and
its risk (startup, active, recovery, landing, shield outcome, spacing). Mark
original values provisional. Query current facts rather than guessing (see
`references/tools.md`).

## Timing, contact and defense

- Per move, author startup, active windows, recovery, cancel windows,
  ground/air eligibility, landing lag, intangibility, resources and
  cooldowns; then damage, launch vector, growth and base, hitlag, shield
  behavior and contact windows (each positive window allows one hit per
  target per attack). Frame 0 is the start tick: startup N means first active
  frame N, display frame N+1.
- Timing is per action and shared by every fighter, except active frames
  (`characterAttackActiveFrames`). A per-fighter startup or total needs a new
  code path; justify it. The clip spans the attack's whole duration, so a
  timing change needs a matching clip; damage, launch or region changes don't.
- Animation informs authored volumes; rendered bones and effect positions
  never decide contact. Test simultaneous contacts and trades through the
  shared resolver.
- Use the shared dodge profile (sim/conditions.ts) unless Tom changes it.
- Recovery: an up-special spends the aerial jump and ends in helpless fall;
  leaving a ledge without jumping keeps one aerial jump. State the fighter's
  recovery reach, ledge options and edge-guard weakness, and make
  match/botRecovery.ts bring the computer back to the stage.
- Use factual Melee data only under `external-code` rules; never copy or
  translate decompiled code.

## Models, presentation, controls and state

- Blender scripts in smashcraft:tools/animations/ author clips;
  `tools/animations/build-assets.sh` and `package.ts` regenerate
  fighterAssetInfo.ts. Never edit generated modules. Proprietary models stay
  under ~/.local/share/smashcraft-build-inputs/ (`repo-safety`). A new model
  needs its asset family in ts/scripts/wisp/mapInputs.ts and an expectation
  in ts/scripts/wisp/playerView.ts.
- Check poses from the side-view camera, both facings, at gameplay size.
  Weapons stay attached, clothing doesn't hide the active limb, and knockdown
  poses lie on the stage. Hit reactions read grounded and airborne. Hitlag
  holds the contact pose for exactly the simulation's hitlag, attacker and
  victim checked separately, without stopping input or the match clock.
  Shield break plays a seamless dizzy loop with starbursts from the shared
  effect system; stock loss and rematch clear it. Effects and sounds get
  stable event IDs so replay never duplicates them.
- Use normalized, rebindable actions; never hardcode keys in move logic. Keep
  jab, tilts, smashes and aerial directions distinct; respect buffering
  through jump squat, facing-relative back air, shield grab and designed
  special cancels. C-stick down-air neither presses Down nor fast-falls.
- Every outcome-changing value lives in the simulation and its snapshots
  (phases, buffers, charge, grabs, resources, projectiles, summons, stable
  IDs, hit registries) and resets on stock loss and rematch. Native handles,
  visuals and audio stay outside replay.
- Selection needs roster chip, portrait, name, HUD plate, mirror match,
  rematch and an off-screen indicator. Player-facing text stays in the game's language.

## Make the change and ship

From smashcraft:ts/:

1. Edit with `bun wisp dev` running. Add a contract test beside the rule it
   pins (pattern: sim/normals.tests.ts) and see it fail without the change.
2. For a move change, run `bun wisp interactions --move FIGHTER:MOVE` before
   and after and note what changed in the commit message. If frame data or
   regions changed, refresh the move-data snapshots (`references/tools.md`).
3. Quick check: `bun run check`, `bun run test`, then play it once in the
   game (`bun wisp hot` into running pool clients, or `bun wisp lan fresh
   MAP`), both facings.
4. `safe-push --to main`. The pre-push hook type-checks; CI runs the Lua,
   parity and perf suites. Fix forward if CI goes red.

## References

| File | Read when |
|---|---|
| `references/source-map.md` | you need the file that owns a part of the fighter (a new fighter touches all of them) |
| `references/moveset.md` | listing every action a new fighter must cover |
| `references/design-reading-list.md` | a design question needs the fighting-game, Melee or interaction-graph sources |
| `references/tools.md` | querying move data, reading the interaction graph, refreshing move-data snapshots, or running the oracle |
| `references/balance-and-release.md` | changing balance or publishing a release (soaks, publication gates, map build, native review) |
