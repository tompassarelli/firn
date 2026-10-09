---
name: testing
description: >-
  Write, change, delete, run or speed up automated tests in any project: what
  earns a test, scaffolding versus durable tests, property, replay and golden
  tests, CPU cost per test, flaky tests, and pruning a suite.
grounded: 2026-10-09
written: 2026-10-09
---

# Testing

A test is an executable rule that no single function can enforce on itself.
Local contracts belong in types, schemas and assertions at the function.
Default to no new test. Test from outside, through the interface a user or
caller sees; a test that knows the internals breaks on refactors and proves
little. Review judges one change once; the suite re-checks every rule on every
future change, so review never replaces it.

## The five kinds that earn a permanent place
1. **Recorded scenarios.** Replay real or seeded input sequences through the
   whole system and check invariants and agreement. Examples: a game match
   whose per-frame checksums agree across runtimes and clients, a request log
   replayed against a service, a document round-tripped through a format.
   Report the first point of divergence. Keep one injected fault that must
   trip the detector.
2. **Properties over a pure core.** Generated inputs against rules that
   always hold: bounds, conservation, symmetry, idempotence, round-trips,
   agreement with a simple reference model. Use fixed seeds and counts
   locally and wide search in CI. Keep a shrunk failure as a named case.
3. **Product measurements.** Numbers the owner decided, with their source:
   latency or frame budgets, balance bands, size limits, quality scores.
   These are CI sweeps, with the smallest form of each in the suite.
4. **External references.** Truth from outside the code: a spec, a reference
   implementation, recorded real-system output. Cite it in the title or
   fixture. An expectation not yet confirmed against the real system stays
   provisional until it is.
5. **One integration check per real boundary**: build, deploy, network
   protocol, file format, external service or device. Each runs the real
   path end to end.

Anything else is scaffolding.

## Scaffolding
- Write throwaway tests freely while you're reaching a solution. Before
  landing, promote each one into one of the five kinds or delete it.
- No regression test for a bug fix unless the five kinds genuinely missed the
  behaviour. Then extend the property, scenario or reference that should
  have caught it.
- No tautologies, no change detectors (snapshots or pins without a rule), no
  expected values derived from the implementation, and no tests of tooling
  or what the compiler or type system already checks.
- No mocks, stubs or injected fakes of your own code. Fake only what you
  don't control (clock, randomness, network, devices), and only by feeding it
  to the core as input.

## Design for fewer tests
- Put the logic in a pure, deterministic core (state + input → state;
  value → value) and test it there with properties and scenarios.
- Keep side effects in a thin shell, typed and scoped: Effect services in TS,
  Result types and RAII in Rust. Test the shell only at its boundary check.
- Make time, randomness and the network inputs to the core (counters, seeded
  RNG in state, simulated peers), so scenarios replay exactly.

## Running
- On each save: the type check, affected tests and one fast end-to-end path,
  in seconds. Every push runs the suite plus sweeps, properties and mutation
  testing in CI or on the farm. Never rerun a passing check on unchanged
  code.
- Bound each test's cost by the repository's ceiling in a deterministic
  quantity (instructions, simulated frames, allocations), never CPU or wall
  seconds; a wall-clock limit is only a generous hang timeout. Shrink inputs
  or move work to CI instead of raising it. Print the seed and commit on
  failure.

## Flaky tests
- Quarantine at first sight with the seed, log and an issue, then fix or
  delete within a week. Cap the quarantine at 8.
- Never retry to green or add sleeps or wider tolerances. Never weaken an
  expectation to pass.

## Pruning
- Audit each existing test against the five kinds. Keep it, fold it into a
  property or scenario, or delete it. Report counts and CPU per test, before
  and after.
- Break the rule once to confirm a kept test fails.
