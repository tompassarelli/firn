---
name: testing
description: >-
  Write, change, delete, run or speed up automated tests in any project: what
  earns a test, scaffolding versus durable tests, property, replay and golden
  tests, CPU cost per test, flaky tests, pruning a suite.
grounded: 2026-10-09
written: 2026-10-09
metadata:
  kind: playbook
---

# Testing

A test is an executable rule no single function can enforce on itself. Local
contracts belong in types and assertions at the function. Default to no new
test. Test through the interface a caller sees; a test that knows internals
breaks on refactors. Review judges one change once; the suite re-checks every
rule on every future change.

## Five kinds earn a permanent place; anything else is scaffolding
1. **Recorded scenarios.** Replay real or seeded input through the whole system
   and check invariants and agreement, e.g. per-frame checksums across runtimes
   or a request log against a service. Report the first divergence. Keep one
   injected fault that must trip the detector.
2. **Properties over a pure core.** Generated inputs against rules that always
   hold: bounds, conservation, symmetry, idempotence, round-trips, agreement
   with a reference model. Fixed seeds locally, wide search in CI. Keep a
   shrunk failure as a named case.
3. **Product measurements.** Owner-decided numbers with their source: frame
   budgets, balance bands, size limits. CI sweeps, with the smallest form in the
   suite.
4. **External references.** Truth from outside the code: a spec, a reference
   implementation, recorded real output. Cite it in the title or fixture; an
   unconfirmed expectation stays provisional.
5. **One integration check per real boundary**: build, deploy, protocol, file
   format, external service or device, run end to end.

## Scaffolding
- Throwaway tests are fine while reaching a solution. Before landing, promote
  each into one of the five kinds or delete it.
- No regression test for a bug fix unless the five kinds genuinely missed it;
  then extend the property, scenario or reference that should have caught it.
- No tautologies, change detectors, expectations derived from the
  implementation, or tests of tooling and of what the type system checks.
- No mocks or fakes of your own code. Fake only what you don't control (clock,
  randomness, network, devices), and feed it to the core as input.

## Design for fewer tests
- Put logic in a pure, deterministic core (state + input → state) and test it
  there; make time, randomness and peers its inputs so scenarios replay exactly.
  Keep effects in a thin typed shell, tested only at its boundary.

## Running and flakes
- On save: type check, affected tests, one fast end-to-end path. Every push runs
  the suite plus sweeps and properties on CI or the farm. Never rerun a passing
  check on unchanged code.
- Bound cost by the repository's ceiling in a deterministic quantity
  (instructions, simulated frames, allocations), never CPU or wall seconds; wall
  clock is only a generous hang timeout. Print the seed and commit on failure.
- Quarantine a flake at first sight with its seed, log and an issue; fix or
  delete within a week; cap the quarantine at 8. Never retry to green, add
  sleeps or widen tolerances, or weaken an expectation.

## Pruning
- Audit each test against the five kinds: keep it, fold it into a property or
  scenario, or delete it. Report counts and CPU per test, before and after.
  Break the rule once to confirm a kept test fails.

Sources for each rule: `references/sources.md`, read only when revising a rule.
