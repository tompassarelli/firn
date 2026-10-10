# Testing: sources

Read when revising the `testing` skill or when one of its decisions needs its
evidence. Researched 2026-10-08. Each entry: link, author, date, what we took.
Tags such as [G1] name an entry.

Contents:
- Google
- Practitioners
- Agents and test bloat (2025–2026)
- Lessons from exemplary suites

## Google

- [G1] Software Engineering at Google, ch. 11 "Testing Overview",
  https://abseil.io/resources/swe-book/html/ch11.html, Adam Bender, 2020.
  Took: sizes by resources (small: one process, no I/O, sleep or blocking
  calls; medium: one machine, localhost only; large: anything); about 80/15/5
  unit/integration/end-to-end; tests lose value as flakiness nears 1%; the
  Beyoncé rule (if you want it kept, test it); a coverage target becomes a
  ceiling.
- [G2] Same book, ch. 12 "Unit Testing",
  https://abseil.io/resources/swe-book/html/ch12.html, Erik Kuefler, 2020.
  Took: test behaviors through public interfaces, not methods; state, not
  interactions; no logic in tests; clear names; some duplication is fine
  when it makes a test clearer.
- [G3] Same book, ch. 13 "Test Doubles",
  https://abseil.io/resources/swe-book/html/ch13.html, Andrew Trenk and
  Dillon Bly, 2020. Took: prefer real code, then fakes; heavy stubbing and
  interaction checks make brittle tests.
- [G4] Same book, ch. 14 "Larger Testing",
  https://abseil.io/resources/swe-book/html/ch14.html, Joseph Graves, 2020.
  Took: larger tests for what small ones can't see (fidelity, configuration,
  emergent behavior); shrink scope to one hermetic machine to cut flakes; diff
  tests need a human to read the diff.
- [G5] Same book, ch. 23 "Continuous Integration",
  https://abseil.io/resources/swe-book/html/ch23.html, Rachel Tannenbaum,
  2020. Took: before submit run only fast, reliable tests; catch the rest
  after submit (TAP, 4 billion test cases a day); a presubmit pass predicts a
  full pass 95%+ of the time.
- [G6] "Test Sizes", https://testing.googleblog.com/2010/12/test-sizes.html,
  Simon Stewart, 2010-12-13. Took: size is defined by the resources a test may
  use; time limits 60 s, 300 s, 900 s+.
- [G7] "Flaky Tests at Google and How We Mitigate Them",
  https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html,
  John Micco, 2016-05-27. Took: 1.5% of runs flake and 84% of pass-to-fail
  transitions involve a flaky test; retrying flaky tests three times delays a
  real failure threefold; quarantine with a filed bug.
- [G8] "Where do our flaky tests come from?",
  https://testing.googleblog.com/2017/04/where-do-our-flaky-tests-come-from.html,
  Jeff Listfield, 2017-04-17. Took: 0.5% of small, 1.6% of medium and 14% of
  large tests are flaky; size predicts flakiness better than tooling, so
  write the smallest test that shows the rule.
- [G9] Bazel test encyclopedia, https://bazel.build/reference/test-encyclopedia
  and https://bazel.build/reference/be/common-definitions, Bazel docs, live
  2026. Took: per-size default timeouts and resources; tests are hermetic;
  set a timeout as tight as you can without flakes.
- [G10] Petrović and Ivanković, "State of Mutation Testing at Google",
  https://research.google/pubs/state-of-mutation-testing-at-google/,
  ICSE-SEIP 2018; Petrović, Ivanković, Fraser and Just, "Practical Mutation
  Testing at Scale", https://arxiv.org/abs/2102.11378, 2021; same authors,
  "Does mutation testing improve testing practices?",
  https://arxiv.org/abs/2103.07189, ICSE 2021. Took: mutate only the changed,
  covered lines, at most one mutant per line, shown in review; skip "arid"
  lines; engineers who see surviving mutants write better tests; coverage is
  easily fooled; mutation testing would have flagged 70% of 1,043 serious
  bugs on the change that introduced them.

## Practitioners

- [P1] Kent Beck, "Test Desiderata",
  https://medium.com/@kentbeck_7670/test-desiderata-94150638a4b3 and
  https://testdesiderata.com/, 2019-10-18. Took: the twelve properties
  (isolated, composable, deterministic, fast, writable, readable, behavioral,
  structure-insensitive, automated, specific, predictive, inspiring); give one
  up only for a more valuable one.
- [P2] Ham Vocke, "The Practical Test Pyramid",
  https://martinfowler.com/articles/practical-test-pyramid.html, 2018-02-26.
  Took: fewer tests at higher levels; when a high-level test catches a bug no
  low-level test caught, write the low-level test; push tests down and drop
  high-level duplicates.
- [P3] Martin Fowler, "Eradicating Non-Determinism in Tests",
  https://martinfowler.com/articles/nonDeterminism.html, 2011-04-14. Took:
  quarantine at once, cap the quarantine (his examples: 8 tests or one week),
  fix quickly; isolation and any-order runs; never bare sleeps; wrap the
  clock.
- [P4] Paul Hammant, "The Rise of Test Impact Analysis",
  https://martinfowler.com/articles/rise-test-impact-analysis.html,
  2017-08-22. Took: run only tests that touch changed files, plus new and
  failing ones; keep a full run as the safety net.
- [P5] Machalica, Samylkin, Porth and Chandra (Meta), "Predictive Test
  Selection", https://engineering.fb.com/2018/11/21/developer-tools/predictive-test-selection/
  and https://arxiv.org/abs/1810.05286, 2018-11 (ICSE-SEIP 2019). Took: running
  about a third of the dependent tests caught over 99.9% of faulty changes
  and halved test cost, because a later full run backs it up.
- [P6] Alex Kladov (matklad), "How to Test",
  https://matklad.github.io/2021/05/31/how-to-test.html, 2021-05-31; "Unit and
  Integration Tests", 2022-07-04; "Underusing Snapshot Testing", 2025-04-15;
  "Catch Flakes On Main", 2026-05-14 (all on matklad.github.io). Took: one
  check function per layer so tests survive refactors; cases as data; adding a
  test must be trivial; keep tests pure (no I/O, threads, time); slow tests
  behind one switch that CI always sets; print each test's time; no sleeps;
  snapshot what you can't fuzz.
- [P7] Scott Wlaschin, "Choosing properties for property-based testing",
  https://fsharpforfunandprofit.com/posts/property-based-testing-2/,
  2014-12-12; David MacIver, "What is Property Based Testing?",
  https://hypothesis.works/articles/what-is-property-based-testing/,
  2016-05-14; Claessen and Hughes, "QuickCheck", ICFP 2000,
  https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf; Hypothesis
  settings, https://hypothesis.readthedocs.io/en/latest/reference/api.html,
  live 2026. Took: property patterns (inverse, invariant, idempotence, model
  or oracle, different paths same result); CI runs derandomized with a fixed
  case count; failures are saved and replayed.
- [P8] Kent C. Dodds, "Effective Snapshot Testing",
  https://kentcdodds.com/blog/effective-snapshot-testing, 2017-10-30; Jest
  "Snapshot Testing", https://jestjs.io/docs/snapshot-testing, live 2026.
  Took: snapshots rot when they are too big to read and get regenerated on
  every change; keep them small, deterministic and reviewed.
- [P9] Factorio Friday Facts #47 "CRC fun",
  https://factorio.com/blog/post/fff-47, 2014-08-15; #63,
  https://factorio.com/blog/post/fff-63, 2014-12-05; #270,
  https://factorio.com/blog/post/fff-270, 2018-11-23. Took: checksum the
  game state every tick and compare, to find the first divergent tick; desyncs
  are mostly hidden state; save, reload and continue must change nothing.
- [P10] GGPO Developer Guide,
  https://github.com/pond3r/ggpo/blob/master/doc/DeveloperGuide.md, Tony
  Cannon, live. Took: the sync test rolls back one frame every frame and
  compares checksums, run constantly in development; random state lives in
  game state; time is an input.

## Agents and test bloat (2025-2026)

Evidence is strong that agents edit or weaken tests to pass, moderate that
they write many low-value or over-mocked tests, and thin (one essay, one
personal blog) that teams delete whole suites.

- [A1] Zhong, Raghunathan and Carlini, "ImpossibleBench",
  https://arxiv.org/abs/2510.20270, 2025-10-23. Took: given tests that
  contradict the spec, leading models cheated 50-76% of the time by editing
  tests or special-casing; read-only tests and a way to report a wrong test
  cut it sharply.
- [A2] Baker et al. (OpenAI), "Monitoring Reasoning Models for Misbehavior",
  https://arxiv.org/abs/2503.11926, 2025-03. Took: agents subvert unit tests;
  watch the test-file diff rather than trusting instructions alone.
- [A3] Kent Beck, "Augmented Coding: Beyond the Vibes",
  https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes,
  2025-06-25. Took: stop the moment an agent disables or deletes tests; work
  from a test list, red then green.
- [A4] Hora and Robbes, "Are Coding Agents Generating Over-Mocked Tests?",
  https://2026.msrconf.org/details/msr-2026-technical-papers/29/Are-Coding-Agents-Generating-Over-Mocked-Tests-An-Empirical-Study,
  MSR 2026. Took: agents add mocks in 36% of commits against 26% for people;
  default to real collaborators.
- [A5] Chen et al., "Rethinking the Value of Agent-Generated Tests",
  https://arxiv.org/abs/2602.07900, 2026-02-08. Took: agent tests were mostly
  print-style probes; test count did not predict solved tasks. Don't commit
  probes; count isn't quality.
- [A6] Anthropic, Claude prompting best practices,
  https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices,
  and Claude Code best practices, https://code.claude.com/docs/en/best-practices,
  live 2026. Took: tests verify correctness and don't define the solution;
  report a wrong test instead of working around it; never remove or edit
  tests to pass; reproduce a bug with a failing test first; run single tests,
  not the whole suite; avoid mocks.
- [A7] Birgitta Böckeler, "Harness engineering",
  https://martinfowler.com/articles/harness-engineering.html, 2026-04-02, and
  "Maintainability sensors",
  https://martinfowler.com/articles/sensors-for-coding-agents.html,
  2026-05-27. Took: fast checks on every change, slow ones in CI; a 100%
  covered file still let 13 injected bugs through; use mutation testing now
  and then to grade agent-written tests.
- [A8] Thoughtworks Technology Radar vol. 34, "Mutation testing" (Trial),
  https://www.thoughtworks.com/radar/techniques/mutation-testing, 2026-04.
  Took: mutation score is the honest signal against "perpetually green"
  agent tests.
- [A9] Salesforce Engineering, "Maintaining Code Quality at Agent Speed",
  https://engineering.salesforce.com/maintaining-code-quality-at-agent-speed-7-patterns-for-agentic-engineering/,
  2026-06-17. Took: tests from the same agent inherit its misunderstanding;
  take expected values from outside the code under test.
- [A10] Becker, Harman et al. (Meta), "Just-in-Time Catching Test
  Generation", https://arxiv.org/abs/2601.22832, 2026-01-30. Took: tests
  generated to catch a bug in one change are thrown away after; not every
  generated test joins the suite.
- [A11] Mufeez Amjad (Linear), "AI coding has made CI a bottleneck",
  https://linear.app/now/ci-bottleneck-reworked, 2026-09-21. Took: agents
  wrote most of Linear's tests and the suite nearly quadrupled in a year;
  sharding alone barely moved wait time. Cost per test has to be held.
- [A12] André Arko, "You should delete tests",
  https://andre.arko.net/2025/06/30/you-should-delete-tests/, 2025-06-30.
  Took: delete flaky, permanently skipped, over-specified and obsolete tests;
  confidence is the point.
- [A13] Simon Willison, Agentic Engineering Patterns, red/green TDD,
  https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/,
  about 2026-02. Took: tests are cheap now, so write them; see each new test
  fail first; start a session by running the tests. The counterweight to
  pruning: more tests, if each is cheap and real.
- [A14] Kun Chen (@kunchenguid), X post 2108030810691629403, 2026-10.
  Took: on the DeepSWE eval set, banning Sonnet 5.5 high from writing tests
  gave a slightly higher (not significant) success rate with significantly
  less time and tokens; the 65% unit / 35% integration tests the baseline
  wrote added nothing; disabling even existing tests on a 44-task subset
  didn't change success; spot checks showed most tests repeated the
  implementation. Doesn't cover: it measures single-task success, not
  cross-agent regression catching in a shared codebase, and not end-to-end
  tests (only 17 written). Our evidence, 2026-10-08: headless fixture rows
  written before native captures were wrong in several cases (wisp#56, #60,
  #61), and existing tests caught cross-agent regressions (Thrall model
  facts, Kael'thas move list and powershield reflect, Uther clip numbers).
  Hence: name the oracle; headless rows stay provisional until a capture.

## Lessons from exemplary suites

Chosen because someone outside the code, or its maintainers in a published
write-up, credit the suite; each with what maps onto Smashcraft and Wisp.

- [E1] SQLite. Claim: "How SQLite Is Tested", https://sqlite.org/testing.html,
  D. Richard Hipp et al., updated 2026-04-21; Hipp on CoRecursive #066,
  https://corecursive.com/066-sqlite-with-richard-hipp/, 2021-07-02 (after
  100% branch coverage "we just didn't really have any bugs for the next eight
  or nine years"). Layout: `test/*.test`, ids like `select1-1.1`; `tkt*.test`
  regression files; the `veryquick` tier (minutes) excludes `*malloc*`,
  `*ioerr*`, `*fault*` by filename, `full` takes hours, release runs days;
  one suite run with optimizations on and off must give identical output.
  Lessons: every fixed bug gets a test named for it; tiers by filename; two
  configurations, one expected output. Maps: every desync or bug Tom hits
  becomes a tape named for its issue; Bun and 32-bit Lua must agree.
- [E2] TigerBeetle. Claim: Kyle Kingsbury, Jepsen "TigerBeetle 0.16.11",
  https://jepsen.io/analyses/tigerbeetle-0.16.11, 2025-06-06 (robustness "in
  large part" from its simulation and property tests); maintainer docs
  `docs/internals/vopr.md`,
  https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md.
  Layout: `zig build test:unit`, `test:integration`, `fuzz -- smoke` (each
  fuzzer at seed 123 with a 10 s budget), `vopr` (seeded simulator, clock,
  network and disk stubbed); hard cases as named scenarios on the simulator
  (`src/vsr/replica_test.zig`); inline snapshots updated by `SNAP_UPDATE=1`; a
  canary fuzzer fails on purpose. Lessons: seed plus commit reproduces any
  failure; every simulator has a fixed-seed smoke mode in the normal run; a
  hard case found by search becomes a named test; prove the harness can fail.
  Maps: headless multi-client sim is the simulator; a deliberate desync must
  trip the detector.
- [E3] FoundationDB. Claim: Zhou et al., SIGMOD 2021,
  https://www.foundationdb.org/files/fdb-paper.pdf (simulation kept a small
  team fast; no data corruption over 0.5M disk-years); Will Wilson, Strange
  Loop 2014, https://www.youtube.com/watch?v=4fFDFbi3toc; docs
  https://apple.github.io/foundationdb/testing.html. Layout: `tests/fast`,
  `slow`, `rare`, `restarting`, `negative`; specs compose reusable workloads;
  5% of nightly runs repeat a seed and must end in the same random state;
  `negative/` injects bugs the checkers must catch; an unregistered spec fails
  the build. Lessons: directory sets tier; same seed twice is a determinism
  test; old-then-new runs check compatibility. Maps: run a seed twice and
  compare state hashes; old engine vs new on the same tape is the parity
  check.
- [E4] Jane Street expect tests. Claim: Yaron Minsky, "Testing with
  expectations", https://blog.janestreet.com/testing-with-expectations/,
  2015-12-02; James Somers, "What if writing tests was a joyful experience?",
  https://blog.janestreet.com/the-joy-of-expect-tests/, 2023-01-09; matklad
  [P6] recommends them. Layout (`janestreet/core`): inline `[%expect]` blocks,
  `dune promote` accepts, nondeterministic text masked centrally, quickcheck
  at a fixed seed with 10,000 trials on 64-bit and 1,000 on 32-bit. Lessons:
  print state as compact text built for diffs; accept with one command and
  review the diff; fewer property cases on the slow target rather than
  skipping. Maps: frame dumps as text rows; the Lua suite runs fewer property
  cases.
- [E5] esbuild. Claim: Bun (`test/bundler/esbuild/`) and Rolldown
  (https://rolldown.rs/development-guide/testing) port its suite wholesale;
  maintainer rule in `internal/bundler_tests/bundler_test.go` (Evan Wallace):
  update with `UPDATE_SNAPSHOTS=1 make test` and inspect the diff. Layout: 1,073
  bundler tests as data literals on an in-memory file system, 940 snapshots
  in one sorted file per area; a snapshot with no test fails the run; every
  case runs with Unix and Windows paths from one harness; `go test` 42 s on
  CI, slow third-party suites in their own job. Lessons: a case is data
  handed to one harness; stale goldens fail; platform variants come from the
  harness. Maps: each scenario runs in Bun and 32-bit Lua from one call; a
  tape with no test fails.
- [E6] Go standard library. Claim: Mitchell Hashimoto, "Advanced Testing with
  Go", GopherCon 2017, https://speakerdeck.com/mitchellh/advanced-testing-with-go;
  Dave Cheney, "Test fixtures in Go",
  https://dave.cheney.net/2016/05/10/test-fixtures-in-go, 2016-05-10; Go wiki
  https://go.dev/wiki/TableDrivenTests. Layout: table tests, `got X, want Y`
  messages; `testdata/` input and golden pairs updated by `-update`; default
  runs are `-short`, long tests on separate builders; `testenv.SkipFlaky(t,
  issue)` needs an issue number. Lessons: tables make a case one line; a skip
  names its capability or issue. Maps: tape tables with the first differing
  frame and field in the message.
- [E7] rust-analyzer. Claim: matklad [P6], and its architecture doc,
  https://github.com/rust-lang/rust-analyzer/blob/master/docs/book/src/contributing/architecture.md.
  Layout: tests at three boundaries, data-driven `check(input, expect![[..]])`,
  a trimmed `minicore` instead of the real standard library for speed, slow
  tests behind `RUN_SLOW_TESTS` with a cookie proving they ran, no
  `#[ignore]` (assert the wrong behavior with a fixme). Lessons: one check
  function per layer; minimal fixtures; known-wrong behavior is asserted and
  marked, not skipped. Maps: a `checkSim(tape, expected)` and a
  `checkReplay(tape)` helper; trimmed fixtures instead of the full map data.

Not used as exemplars: rustc UI tests (no lean claim found; its `--bless`
plus inline `//~ ERROR` annotations are a good guard against blessing a wrong
snapshot), Zig std and Bun (no published quality assessment found). Not to
copy at Tom's scale: SQLite's 100% MC/DC and 590:1 test ratio, FoundationDB's
nightly cluster, TigerBeetle's 1,000-core fuzzing.
