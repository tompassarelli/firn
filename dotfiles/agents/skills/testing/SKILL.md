---
name: testing
description: >-
  Write, change, delete, run or speed up automated tests: what earns a test,
  its level and tier, CPU cost per test, flaky tests, golden, property and
  deterministic match tests, and pruning slow or vanity tests.
---

# Testing

Tests pin behavior Tom wants kept, so a broken rule fails a test before he
finds it in play. Cut cost and waste; keep or grow coverage of real behavior.
Tags like [G1] name the evidence in `references/sources.md`; read it when
revising this skill or when a decision here needs its source.

## What earns a test

- Before writing a test, name its **oracle**, where the expected value comes
  from: a real-game capture, a value Tom or a design doc set, a reproduction
  that fails on the old code, or an invariant that holds however the code
  computes it (matching checksums, frame-for-frame replays, no desync). A
  test whose expected value came from running the code you just wrote is a
  restatement of the implementation; don't write it. Headless expected rows
  stay provisional until a native capture confirms them. The title carries
  the oracle tag: `[native]`, `[reference]`, `[spec #N]`, `[repro #N]`,
  `[invariant]` or `[provisional]` (headless, awaiting a native capture);
  runners refuse an untagged test. No oracle: delete it. [G1, E1, A14]
- Add a test wherever a rule is unpinned. Every fixed bug gets one named for
  its issue; netcode and invariants get one even when the code looks right.
- One rule or defect per test, said in the title: `[spec #12] shield breaks
  at 0 and stuns 120 frames`, `[repro #181] low projectile hits a crouching fighter`.
  Failures print `got X, want Y` and the case name. [E6, P1]
- Test behavior through the path the product runs, so a refactor that keeps
  behavior keeps the test green. Real code first, then fakes; a mock that
  replays calls pins nothing. [G2, G3, A4]
- Adding a case should cost one line: extend an existing table first. [P6, E6]

## Pick the cheapest level that runs the real code

| Size | May use | Use for |
| --- | --- | --- |
| small | one process; no files, network, sleep or clock | rules, formulas, one sim step, tables |
| medium | one machine: files, subprocesses, localhost | headless multi-client match, 32-bit Lua, replay tapes |
| large | real game clients, real network | what only the real client shows |

Flakiness rises with size (0.5% small, 14% large at Google), so go down a size
whenever it runs the same code; when a larger test catches a bug, add the
small test that should have. [G1, G6, G8, P2]

- **One check function per layer** (`checkSim(tape, expected)`,
  `checkReplay(tape)`); cases are data handed to it. A refactor edits one
  function, not every test. [P6, E5, E7]
- **Golden tests** for structured output (per-frame state, emitted Lua,
  command text): compact text, one row per frame, compared to a checked-in
  file. Accept with the repo's update command, read the diff, commit it with
  its cause. A golden with no test fails the run. Mask nondeterministic text
  in one place. Never regenerate goldens wholesale to get green. [E4, E5, P8]
- **Property tests** for invariants (damage never negative, rollback then
  replay equals straight play): fixed seed and case count in the suite, wide
  search on the farm; on 32-bit Lua run fewer cases, don't skip. A failure
  found becomes a named test with the shrunk input. [P7, E2, E4]
- **Both runtimes, one harness**: each scenario runs in Bun and 32-bit Lua
  and must give the same output. [E1, E5]

## Simulate, don't wait

Match, netcode and replay tests are deterministic simulations: a fixed seed,
a frame counter for time, simulated clients for network, random state inside
game state. Every failure prints seed and commit; those reproduce it. [E2,
E3, P10]

- Check determinism directly: play a seed twice, and roll back one frame
  every frame (GGPO's sync test), comparing state checksums each frame; report
  the first differing frame and field. [P9, P10, E3]
- Keep a canary: a scenario that injects a desync must trip the detector, so
  a broken harness can't pass. [E2, E3]
- A hard case found by search becomes a named scenario on the simulator.
- One seeded match per invariant in the suite; many matches, all pairs and
  random seeds on the farm.

## Tiers and where they run

| Tier | When | Budget | Holds |
| --- | --- | --- | --- |
| every save | dev watcher after each save | seconds in total | type check, affected tests, one headless journey |
| suite | farm on every push; locally only affected tests | the repo's CPU ceiling per test | rules, reference values, defects, one seeded match per invariant |
| farm | every push, own jobs; a failure marks main red | per job | sweeps, many matches, all pairs, balance, calibration, soak, wide property search, mutation runs |
| native | real clients, batched per client lane | per lane | checks only the real game can decide |

Mark the tier in the file name or directory, not flags inside tests; a
skipped tier says it was skipped. A sweep that guards an invariant keeps its
smallest form in the suite. [E1, E3, E7, G4]

## Run only as wide as the change

- Locally, run the affected tests: the dev watcher, or the file with
  `-t NAME`. Never the full suite on Tom's machine. [A6]
- The farm runs everything on every push; that is what makes selection safe.
  Meta ran a third of the tests and still caught 99.9% of bad changes. [P4, P5,
  G5]
- Don't re-run a passing test on unchanged code.

## Cost

- Measure CPU time (user plus system) per test and per file; wall time on a
  loaded machine is a guess. The runner prints both and the suite's CPU per
  test. [P6]
- The repo's `AGENTS.md` sets the CPU ceiling per test. The runner fails a
  test over it and a file whose cost rises without new tests. No cap on test
  count: CPU per test holds or falls as the suite grows. [G9, A11]
- Over the ceiling: shrink the input, go down a size, share read-only setup
  per file, use trimmed fixtures instead of the full game data, or move the
  test to the farm. Never raise the ceiling to fit a test. [E7]
- To speed up a suite, post the per-file CPU table, then cut from the top:
  sweeps inside the suite, several matches where one shows the rule, per-test
  setup, real-time waits.

## Flaky tests

- Passes and fails on the same code: flaky. Never retry it to green or hide
  it with a retry, sleep or wider tolerance. [G7, P3]
- At first sight, file an issue with seed and log and skip the test with the
  issue number in the same commit; it keeps running on the farm without
  blocking. Fix or delete it within a week; at most 8 in quarantine, and a
  full quarantine comes before new work. [P3, E6]
- Fix the cause: unseeded random, wall clock, order dependence, shared state,
  an unawaited async step, resource limits. [P3, G8]
- Behavior known to be wrong is asserted as it is now with the issue number,
  not skipped. [E7]

## Delete and shrink

Delete on sight, each in a commit that lists it and why: [A12]

- **Restates the code**: a constant, table or config value copied from the
  source. A value from an outside source is a reference test; cite it, keep it.
- **Checks what a tool could**: source shape, layout, wording or types the
  compiler, type checker or a lint decides. Move it there if it matters.
- **Tests the tooling**, the framework or a mock.
- **Duplicates** a rule a cheaper test pins through the same path. [P2]
- **Asserts nothing**: only that code runs, a print-style probe, or a golden
  nobody reads. [A5, P8]

To tell load-bearing from noise, break the rule in the code (flip the
comparison, drop the branch, move the threshold) and run its tests. If its
test doesn't fail, fix or delete it; if no test fails, add one. The farm runs
mutation testing on changed lines now and then; coverage finds unpinned code
but a percentage is not a goal. [G10, A7, A8]

Never delete a test that pins a rule, reference value or defect to save time:
shrink it, go down a size, or move it to the farm.

## Writing a test

1. Write the rule or issue as one sentence: the title.
2. Extend an existing table, else use the cheapest level that runs the path.
3. Smallest input that shows the rule: one fighter, one seeded match, values
   just below and at each threshold.
4. Expected values from the named oracle, cited; never from the code's output. [A9]
5. Watch it fail: a defect test before the fix; a rule test by breaking the
   rule once. [A3, A6, A13]
6. Deterministic and independent: fixed seed, no clock, no network, any order.
7. Never weaken a test to pass: no changed expected values, looser
   tolerances, skips or deletions. If a test looks wrong, stop and say so.
   When Tom changes a rule, update its values in the same commit and name the
   rule in the message. [A1, A2, A6]

Write every test the change's rules need and nothing else; throwaway probes
are not committed. [A5, A10]
