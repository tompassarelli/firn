# Balance changes and releases

Read this only when changing balance or publishing a release. Ordinary fighter
and move work follows the short procedure in SKILL.md and lets CI gate.

## Soak before and after

**Baseline.** Before editing, record the soak you will compare against:
`SOAK_OUTCOMES=FILE bun wisp soak --policy cpu --matches 540 --seed 2 --minutes 20`.
Computer-vs-computer matches are deterministic; fuzz matches vary slightly
between runs of the same code, so read them as noise of a few matches.

**After soak and record.** Same soak command and seed;
`bun scripts/soakOutcomes.ts FILE` summarizes each run. Put the raw
files and a README in smashcraft:evidence/<topic>-<yyyymmdd>/, add a
before/after section to smashcraft:docs/move-comparisons.md, and correct
any doc sentence that states the old value.

## Publication gates

**Publication gates.** Merge `origin/main` (and rerun
`bun install --frozen-lockfile` when it changed ts/wisp.lock), then `bun run check`,
`bun run test`, `LUA=<lua32> bun scripts/lua-tests.ts`,
`LUA=<lua32> bun wisp tapes` and `LUA=<lua32> bun wisp parity numeric`
(both also need a toward-zero Lua: `TOWARD_ZERO_LUA`, or built with nix
on first use), `bun scripts/unused-code.ts`, `bun wisp oracle`,
`CI_TIMING=report bun scripts/ci.ts`, then `safe-push --to main`.

## Map build

**Map build.** Reuse the newest candidate's private inputs: the first
line of ~/.local/share/smashcraft-build-inputs/playable-00NN/build*.log is
its exact command (smashcraft:docs/playable-00NN.md can lag behind it):
`bun wisp build --profile main|playable --base BASE.w3m --container CONTAINER.w3x --assets DIR --summon DIR --name NAME --out OUT.w3x`.
A diagnostic build takes its own name and folder, never the next
`Smashcraft 0.0.N`; only a release candidate takes that number.

## Native check by the native owner

**Native, by the native owner only.** Name the exact map and commands
for them: `bun wisp fresh MAP.w3x` (development profile, `-dev quick`),
`bun wisp hot --data A --data B --watch` for later saves,
`bun wisp parity capture --bot ...` for a bot session
(smashcraft:docs/native-bot-session.md), `bun wisp view scene DIR`.
Check both facings and a mirror match, animation against the active
frames, contact readability, UI, and stock and rematch reset.

Report source-tested, built and native-observed behavior separately. Soak
and frame data do not establish balance; Tom can veto any tuning.

## Keep claims to their sources

Input timing claims cite #26's bounded historical result, the current
regression and acceptance in #60, and stall recovery in #48; never restate
them from a character change. Don't reopen viability research or add Wisp or
framework work without a concrete blocker; a Wisp change goes through its own
lane and `bun run update:wisp`.
