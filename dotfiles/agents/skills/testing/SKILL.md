---
name: testing
description: >-
  Write, change, delete, run or speed up automated tests: what earns a test,
  its level and tier, CPU cost per test, flaky tests, golden, property and
  deterministic match tests, and pruning slow or vanity tests.
---

# Testing

- Read [sources](references/sources.md) only for an unresolved source or when revising this skill.
- Name an oracle before writing a test: native capture, reference value, design rule, old-code reproduction, or independent invariant.
- Tag each title `[native]`, `[reference]`, `[spec #N]`, `[repro #N]`, `[invariant]`, or `[provisional]`.
- Keep headless expected rows provisional until native capture confirms them.
- Delete a test without an oracle.
- Never derive expected values from the implementation's output.
- Pin every untested rule, fixed bug, netcode rule and invariant through the product's real path.
- Name one rule or defect per title; print the case and `got X, want Y` on failure.
- Extend an existing table before adding a harness.
- Use one check function per layer.
- Choose the cheapest level running real code: small = one process without files/network/sleep/clock; medium = one machine with files/subprocesses/localhost; large = real clients/network.
- Add a smaller regression test when a larger test finds a bug.
- Keep golden output compact and checked in; mask nondeterminism once, read update diffs, and commit their cause.
- Fail on a golden without a test.
- Never regenerate goldens wholesale to get green.
- Use fixed seeds and case counts for properties; search widely on the farm and retain shrunk failures as named cases.
- Run fewer property cases on 32-bit Lua rather than skipping them.
- Require matching Bun and 32-bit Lua output from one harness for each applicable scenario.
- Simulate time with frame counters and network with simulated clients.
- Keep random state inside game state.
- Print seed and commit for every simulation failure.
- Compare checksums per frame for replaying a seed twice and rolling back one frame every frame.
- Report the first differing frame and field.
- Keep a desync-injection scenario that must trip the detector.
- Keep one seeded match per invariant in the suite.
- Send many matches, all pairs and random seeds to the farm.
- Mark tiers in filenames/directories, and report skipped tiers explicitly.
- Run type checks, affected tests and one headless journey on every save, within seconds total.
- Run only affected tests locally with the watcher or file/`-t NAME`.
- Run the suite and separate sweep/property/mutation jobs on the farm on every push.
- Keep the smallest form of each sweep invariant in the suite.
- Batch native-only checks per client.
- Never rerun a passing check on unchanged code.
- Measure user-plus-system CPU per test/file and print wall time and suite CPU per test separately.
- Enforce the repository's CPU ceiling, non-rising file cost without new cases, and held/lowered CPU per test as coverage grows.
- Shrink inputs, lower test size, share read-only file setup, trim fixtures, or move work to the farm instead of raising the ceiling.
- Post a per-file CPU table before speeding up a suite; remove its largest avoidable costs first.
- Quarantine a test that passes and fails on unchanged code at first sight, with seed/log and an issue-linked skip in the same commit.
- Keep it running nonblocking on the farm.
- Fix or delete quarantined tests within one week.
- Cap quarantine at 8 and clear a full quarantine before new work.
- Fix the flaky cause.
- Never retry to green or add retries, sleeps or wider tolerances.
- Assert known wrong behavior with its issue number instead of skipping it.
- Delete implementation restatements, compiler/lint checks, tooling/framework/mock tests, cheaper-path duplicates and assertions that pin nothing; list deletions and reasons in the commit.
- Retain cited outside reference values.
- Shrink or move tests pinning rules, references and defects instead of deleting coverage.
- Break the rule once to check its test fails.
- Fix or delete ineffective tests and add a missing rule test.
- Use changed-line mutation testing on the farm.
- Use coverage to locate unpinned code rather than targeting a percentage.
- Write the title, choose the real path, supply the smallest threshold/input case, cite the oracle, and observe failure before fixing a defect.
- Keep tests deterministic, independent and runnable in any order.
- Never weaken expectations, tolerances or coverage to pass.
- Report a suspected wrong test, or update a Tom-changed rule and its values in the same named commit.
- Commit only tests the changed rules need, excluding throwaway probes.
