# Tool commands

From smashcraft:ts/ unless noted. Heavy runs go through the machine-capacity helper.

## Query move facts

From the repository root:

```sh
jq 'select(.kind == "contact" and .character == 1 and .move == "down-tilt")' tools/move-data/moves.jsonl
```

Character IDs, move names and row kinds are in smashcraft:docs/move-data.md;
bot-soak balance data in smashcraft:evidence/soak-*; trade-off method in
smashcraft:docs/move-reference-join.md.

## Interaction graph

The graph is not committed; each checkout writes its
own. Before the change, write it with `bun wisp interactions`. After it,
`bun wisp interactions --move FIGHTER:MOVE` (about 10 s, capacity scope)
compares against that graph: read where the move wins, loses and punishes,
and record what changed in the commit message. Never commit
smashcraft:tools/move-data/interactions/.

## Move data snapshots

From the repository root, in this order, because the
reference join reads the checked-in snapshots:
`tools/move-data/export.sh --check`, then `compare.sh --check` (it also
runs `interactions --check`, which fails until the interaction graph above was rewritten),
then `reference.sh --check`. On a difference, diff
smashcraft:build/move-*/ against smashcraft:tools/move-data/, confirm only
intended rows changed, copy the generated file over the snapshot and
check again. `bun run test` doesn't run these checks.

## Shared-rule and headless checks

`bun wisp oracle` (0 mismatches; it checks shared rules
and borrowed movement, not move damage). A new fighter declares the rows
it borrows in ts/scripts/meleeOracle.ts. `bun wisp headless` plays the
quick match in two simulated clients (`headless desync` is a detector
self-test that must report a desync, not a gate).
