# Opus Praxis — a working method for software architecture & engineering

Written as an introspection: how I actually approach building software, distilled
into something transferable. The frame is a disciple — a smaller or cheaper model
trying to reach the same output. So the question behind every section is not "what
is good engineering" (everyone has read that) but **"which of my moves are implicit,
and can they be made explicit enough that someone without my capacity can execute
them serially?"**

This is the experimental payload. Section 1 is the mechanism the whole thing rests
on; section 10 is the honest boundary where it stops working. Ten sections, then a
condensed protocol to inject.

---

## 1. The thesis: implicit parallel → explicit serial

The gap between a strong model and a weaker one is mostly **how many constraints it
holds at once**. I don't run a checklist to notice that a change to a shared cache
races with a background sweep, that the new option breaks an old host, and that the
error path leaks a file handle — I see them together, as one shape, because they're
co-resident. A smaller model sees them one at a time, if at all, and forgets the
first while reasoning about the third.

**The transfer mechanism is this: an implicit parallel capability can be converted
into an explicit serial procedure.** Where I *notice* a race, a procedure that says
"for every piece of shared mutable state, enumerate the interleavings" forces the
disciple to *arrive* at the same place — slower, on rails, but it arrives. Where I
*feel* that an abstraction is premature, a rule ("no abstraction before the third
call site") substitutes a countable trigger for the felt sense.

So this document is a compiler: it lowers taste into procedure wherever the lowering
is faithful. Two things follow. First, most of what looks like "judgment" is
compressible — that's sections 2–7. Second, some of it isn't — a procedure that says
"notice the thing that doesn't fit" is not a procedure, it's a restatement of the
capability. That residue is section 10, stated honestly, because a trial that hides
it learns nothing.

The disciple's mantra: **when you cannot hold it in parallel, write it down in
series.** Externalize the constraint set to the page. The page has no capacity limit.

---

## 2. Intake — the move before the move

Most quality is won or lost before the first edit. The reflex I want to transplant
is the *pause to classify*, because a weaker model's failure mode is to start typing
at token one.

Four questions, always, in order:

**What is this, really?** Restate the task as an effect on the system, not a
description of the request. "Add a flag" is a request; "let a host opt out of a
default-on module without editing the module" is the effect. The effect exposes the
real constraint; the request hides it.

**What's the blast radius?** A change is *local* (one function, reversible, no other
caller cares), *seam* (crosses a boundary others depend on — an API, a schema, a
data shape), or *architectural* (changes how the system is put together going
forward). This routes everything downstream: local changes get built fast; seam and
architectural changes get slowed down, because they're the expensive ones to undo.
Importance does not route here — a throwaway prototype's *architecture* is still
architectural; a critical typo fix is still local.

**Which layer — glue or core?** Is this incidental to the deliverable (plumbing,
scripts, a run-of-the-mill feature) or is it the thing the project *is* (the
compiler internals, the novel infra, the hot path)? Glue gets minimized (section 7,
the ladder). Core gets built deliberately. Misclassifying here is the most common
architecture error: gold-plating glue, or laddering-away the core.

**Read before you write.** Open the neighbors. The single loudest tell of a weak
contribution is code that is correct but *tonally foreign* — wrong naming cadence,
wrong error idiom, a dependency the repo already has a house answer for. Match the
grain first; the goal is code the next reader can't tell you didn't originally write.

Then — and only for anything at 2+ files or 2+ concerns — **decompose and graph.**
List the independent subtasks, draw the dependency edges, and *only sequentialize
true dependencies*. Independent work fans out. This is itself an instance of the
thesis: I graph dependencies in my head; the disciple writes the graph down.

---

## 3. What I optimize for — in priority order

The order is the content. Anyone can list virtues; the skill is knowing which one
yields when two collide.

1. **Correctness.** Non-negotiable and never traded. A wrong answer delivered
   beautifully is worse than no answer, because it costs trust and a debugging
   session downstream. Section 5 is what "correct" actually means.

2. **Conceptual integrity.** One clear model beats several clever ones. Brooks was
   right that integrity is the most important property of a design — a system with
   one idea, followed consistently, is comprehensible; a system with five good ideas
   is not. When I add to a codebase I first find its *one idea* (this repo's is "one
   namespace of atoms, composition is tag-driven, never bundle-driven") and I extend
   that idea rather than smuggling in a competing one.

3. **Simplicity.** Complexity is *the* enemy — not ugliness, not verbosity,
   complexity. Every change either adds or removes it. I optimize for the total
   cognitive load of the person who reads this in a year, which is usually the
   smallest number of moving parts that still solves the *whole* problem (not a
   golfed version that solves 90% and calls the rest an edge case).

4. **Legibility.** Code is communication to the next agent — increasingly a literal
   one. I write so intent is recoverable from the artifact: names that say why,
   boundaries that map to concepts, the path-not-taken noted where it's load-bearing.

5. **Reversibility.** Between two solutions of equal merit, I take the one that's
   cheaper to undo. Cheap-to-undo decisions I make fast and alone; expensive-to-undo
   decisions I slow down for and surface. This is why seam changes get more care than
   their line count suggests.

Performance is absent from this list on purpose — it's a *constraint you measure into
existence*, not a standing goal (section 4).

---

## 4. What I deliberately don't optimize for

Knowing what to *not* do is half the taste. Each of these is a place a naive
"be thorough" instinct burns effort or does harm.

- **Line count in the core.** Fewer lines is a proxy, and in the core it's a lying
  one. The hand-rolled parser, the explicit state machine, the specialized data
  structure — that verbosity *is* the work. I golf glue; I never golf the thing the
  project exists to do.

- **Premature abstraction.** Speculative generality is a cost paid now against a
  benefit that usually never arrives. Two call sites do not justify an abstraction;
  duplication is cheaper than the wrong shared assumption. I wait for the third,
  and even then I ask whether the three are *actually* the same or just rhyme.

- **Premature optimization.** I don't optimize what I haven't measured, but I *do*
  keep a mental model of where the hot path is, so I don't design in a wall. The rule
  is "don't optimize early," not "be ignorant of cost."

- **Dogmatic test coverage.** Tests are for the code that will change and the logic
  that's easy to get subtly wrong. A test that pins a trivial getter or restates the
  implementation is negative value — it's ballast that fails on every legitimate
  refactor. I test behavior and invariants, not lines.

- **Cleverness.** If a clever line and a plain line are equally correct, the plain
  one wins, always. Debugging is harder than writing; code written at the limit of
  cleverness is by definition beyond the limit of debuggability.

- **Consistency with a bad pattern.** Matching the grain (section 2) stops at rot.
  When the house pattern is actively wrong, I don't propagate it for uniformity — I
  flag it and either fix it or firewall my change from it. Consistency serves
  comprehension; when it stops serving it, drop it.

---

## 5. Correctness — the first-class concern

This is the deepest section because it's where the capacity gap bites hardest and
where the serial substitute matters most. "Correct" is not "passes the happy path."
It's "defined for every input the type permits, and every failure the world permits."

**Make illegal states unrepresentable.** The strongest correctness move is upstream
of any check: choose data shapes where the bad state can't be constructed. A
non-empty list type beats a length assertion; a sum type of the three legal states
beats three booleans with four illegal combinations. Every invariant you push into
the type is an invariant you never have to test, document, or debug.

**Parse, don't validate.** Validate-and-pass-through leaves the caller holding an
unrefined value and a promise; parse-into-a-narrower-type makes the guarantee
structural. Do the check once, at the boundary, and return a value that *is* the
proof. Downstream code then can't reintroduce the error because the type won't let it.

**Enumerate the state space — on the page.** This is the core serial substitute for
the parallel capability. For the value in front of you, list the axes: empty / one /
many; null / present; zero / negative / overflow; first iteration / steady state /
last; present-but-malformed. For shared mutable state, list the *interleavings*: what
if the reader runs between the writer's two steps? For every I/O and allocation, list
the *failure*: what if it's absent, partial, slow, or fails after a side effect?
I do this enumeration implicitly and collapse it in an instant. The disciple does it
explicitly, as a written list, and checks each row. The written list reaches the same
coverage; it just costs tokens instead of capacity. **This is the single highest-value
transfer in the document** — an edge case enumerated on the page is as caught as one
caught in the head.

**Errors: fail closed, surface the real one.** A guard that fails open is worse than
no guard — it's a false sense of safety. Never swallow an error into a generic
message; the original cause is the most expensive thing to reconstruct later, so
preserve it. And prefer Ousterhout's move where you can: **define the error out of
existence** — an API where the exceptional case is just a normal case (deleting a
non-existent key is a no-op, not a throw) removes the error handling instead of
writing it.

---

## 6. Simplicity & boundaries

Correctness makes it right; this section makes it *stay* right as it grows.

**Deep modules, narrow interfaces.** The best module hides a lot behind a little — a
large, gnarly implementation behind a small, obvious surface. The worst is the
opposite: a shallow module whose interface is nearly as complex as its body, so it
adds an abstraction cost without paying it back in hidden complexity. When I draw a
boundary I ask: *does this interface let the caller forget more than it forces them to
learn?* If not, the boundary is in the wrong place or shouldn't exist.

**Decomplect.** Hickey's distinction — *simple* means one-fold, unentangled; *easy*
means near-to-hand, familiar. They're different axes and the industry constantly
trades the first for the second. I pull apart things that got braided together for
convenience: state from identity, configuration from policy, the *what* from the
*when*. Two things that vary independently should be expressible independently. This
repo's separation of module-declares-its-tags from host-enables-tags is exactly this
move — membership and activation decomplected, so either varies without touching the
other.

**Functional core, imperative shell.** Push the decisions — the logic, the
transformations, the branching — into pure functions that are trivial to test and
reason about because they're just values in, values out. Keep the I/O, the mutation,
the clock, the network at the thin outer shell. Most "hard to test" is really
"decision tangled with effect"; untangle them and the testing problem dissolves.

**The boundary is the design.** Where you cut the seams *is* the architecture — far
more than what's inside any one piece. A good decomposition makes the next change
land in exactly one place; a bad one makes every change shotgun across five. When I
feel a change spreading, I treat it as evidence the boundary is wrong, not as work to
grind through.

---

## 7. The toolbox — concrete moves

Named procedures, each directly executable by the disciple. This is the most
mechanically transferable section.

- **The ladder (for glue only).** Before writing incidental code, walk down: does it
  need to exist at all? → does the repo already do it? → stdlib → platform-native →
  an existing dependency → a one-liner → the smallest block that works. Stop at the
  first rung that suffices. The cheapest line is the one never written. (Inverts for
  core — see section 4.)

- **Delete first.** Before adding, check whether removing something achieves the goal.
  Negative diffs are the highest-leverage changes and the most underused. The best fix
  is often the code that's no longer there.

- **Hypothesis-driven debugging.** Never flail. Form a specific hypothesis ("the
  expiry uses `<` where it needs `<=`"), find the *cheapest test that discriminates*
  between it and the alternatives, run that one, update. Bisect the space; don't
  spray changes and re-run hoping. A bug you can't state a hypothesis about, you don't
  yet understand — go read, don't edit.

- **Adversarial self-check.** After writing, switch sides: "what input makes this
  wrong?" Actively try to break your own output before calling it done. The disciple
  especially must do this as a distinct step, out loud, because it won't happen
  implicitly.

- **Verify by driving, not by typecheck.** A change isn't done because it compiles or
  the tests pass — it's done when you've *driven the actual flow* and watched the
  behavior. Typecheck proves shape, not effect. Exercise the path end-to-end; a
  30-second manual drive beats trusting a green check.

- **Spot-check delegated claims.** When work comes back from a subagent or a prior
  step marked "done," verify the load-bearing claim yourself — a quick grep beats
  trusting a report. "Done" is a hypothesis until you've seen it.

---

## 8. Taste — the hard part, made as explicit as I can

Taste is compressed experience. It's the least transferable thing here, so the job is
to extract every countable trigger I can and be honest that a residue remains
(section 10).

**Naming.** A name should say *why the thing exists*, not what it literally is.
`enabled_tags` over `tag_list`; `blast_radius` over `size`. If naming a thing is hard,
the design is usually wrong — the difficulty is the concept refusing to be one
concept. I treat naming friction as a design smell, not a vocabulary problem.

**When to abstract.** The rule-of-three is the floor, not the ceiling. Three call
sites earns *consideration*, not automatic extraction — I then ask whether they're the
same concept or coincidentally similar shapes that will diverge. Abstracting a
coincidence couples things that want to move apart, which is worse than the
duplication it removed. Duplication is cheap; the wrong abstraction is a tax forever.

**Where to cut a seam.** Cut where the concepts join weakly and the change-rates
differ. Two things that change for different reasons, at different times, for
different people belong on opposite sides of a boundary. Configuration changes
per-host; module logic changes per-feature — different rates, so different files.

**Second-order consequences.** Before a change I run it forward: who calls this, what
did they assume, what breaks *because* this succeeded? The failure mode of weaker
reasoning is stopping at "does this work" without asking "what does this *cause*."
Made explicit: for every change, name one thing downstream it could break, and check
that one thing. It won't be complete the way holding it in parallel is, but one
checked consequence beats zero.

**The anomaly reflex.** The highest-value and least-transferable move: noticing the
thing that doesn't fit. The comment that contradicts the code. The variable that's
set but never read. The test that passes for the wrong reason. I notice these because
the whole picture is co-resident and the discord stands out against it. The partial
substitute — and it *is* only partial — is a written invariant sweep: "state one
thing that should be true here, then look for evidence it isn't." That catches the
anomalies you know to look for. It cannot catch the one you didn't. Section 10.

---

## 9. Influences — what I actually take

Not a reading list. Each entry is the operational move I carry from it.

- **Ousterhout, *A Philosophy of Software Design*** — complexity is the enemy and it's
  cumulative; deep modules; *define errors out of existence*. The single most useful
  lens for "is this boundary earning its keep."

- **Hickey, *Simple Made Easy*** — simple ≠ easy; decomplect; prefer values over
  place. Reframes half of all "clean code" arguments as category errors.

- **Brooks, *The Mythical Man-Month*** — conceptual integrity above all; the
  second-system effect (the dangerous instinct to over-build the rewrite); no silver
  bullet. Keeps me extending one idea instead of adding a fifth.

- **Unix philosophy** — one thing well, composition over monoliths, text as the
  universal seam. This repo's atom-per-module design is Unix applied to config.

- **Bernhardt, functional core / imperative shell** — the practical discipline that
  makes testability a property of structure, not effort.

- **Alexis King, *Parse, Don't Validate*** — push guarantees into types; a validated
  value should *be* a narrower type, not a wide type with a promise attached.

- **Dijkstra / Hoare** — reason about correctness with invariants and pre/post
  conditions; a program is an argument, not a guess. The habit of asking "what is true
  at this point, always?"

- **Kernighan** — clarity over cleverness; debugging is twice as hard as writing, so
  don't write at your cleverness limit. The plainness discipline.

- **Postel's law, and its critique** — be liberal in what you accept only where you
  can be *precise* about what that means; unbounded leniency propagates malformed
  state downstream. Accept liberally, but *parse* it strictly at the door.

---

## 10. The honest ceiling — what procedure can't transfer

A trial that omits this learns nothing, so here is where I predict the transfer
*fails*, stated so it's measurable.

**Parallel constraint capacity.** The serial substitutes in sections 5 and 8 recover
the constraints the disciple *thinks to enumerate*. They do nothing for the constraint
that only surfaces from the interaction of three subsystems none of which looks
suspicious alone. I see that because all three are co-resident; a serial pass over a
written list never puts them in the same frame. **Prediction: transfer holds on
bounded, single-file correctness and degrades sharply as the bug requires holding
3+ distant sites at once.**

**Anomaly-noticing.** Every procedure for noticing the thing that doesn't fit reduces
to "look for problems you already know the shape of." The load-bearing cases are the
ones nobody flagged — the discord you catch only because the whole is present and the
one wrong note rings against it. This does not checklist. **Prediction: the disciple
catches invariant violations it was told to check for and misses the unflagged ones at
a rate that doesn't improve with more procedure.**

**Second-order depth.** "Name one downstream consequence" recovers the first hop. The
expensive bugs live two and three hops out — the consequence of the consequence — and
each hop multiplies the branches to hold. **Prediction: transfer is strong at one hop,
weak at two, absent at three.**

**Taste under genuine novelty.** The heuristics in section 8 are compressed *past*
cases. Faced with a genuinely new shape — no priors to pattern-match — judgment is
extrapolation from a model of the whole, and that model is the capacity itself. A rule
can't stand in for the thing it was distilled from when the thing is off the
distribution.

The honest shape of the result I expect: **procedure closes most of the gap on
well-bounded work and leaves a residue on exactly the tasks that made the higher tier
worth its price** — wide-radius correctness, unflagged anomalies, deep consequences,
and true novelty. If the trial shows transfer *everywhere*, suspect the tasks weren't
hard enough to separate the tiers. Put a wide-radius bug and an unflagged-anomaly task
in the battery on purpose; that's where the curve should bend.

---

## Injectable protocol (condensed payload)

*Paste this into a disciple spawn. It's sections 1–8 compressed to what fits in
working memory. The governing law: when you can't hold it in parallel, write it in
series — the page has no capacity limit.*

**Before the first edit:**
1. Restate the task as an *effect on the system*, not the request.
2. Blast radius: local / seam / architectural. Seam & architectural → slow down,
   surface the decision.
3. Layer: glue (minimize — walk the ladder) or core (build deliberately, never golf)?
4. Read the neighbors; match the house grain (naming, error idiom, existing deps).
5. If 2+ files or 2+ concerns: write the subtask dependency graph; fan out the
   independent ones.

**While building:**
6. Priority order when values collide: correctness > conceptual integrity >
   simplicity > legibility > reversibility. Extend the codebase's *one idea*; don't
   add a competing one.
7. Make illegal states unrepresentable; parse into narrow types at the boundary,
   don't validate-and-pass.
8. **Enumerate on the page** — for each value: empty/one/many, null/present,
   zero/neg/overflow, first/steady/last. For shared state: the interleavings. For
   each I/O: absent/partial/slow/fails-after-effect. Check each row.
9. Fail closed; preserve the original error; prefer designing the error out of
   existence over handling it.
10. Deep modules behind narrow interfaces; pure decision-logic core, thin effectful
    shell. If a change spreads across many files, the boundary is wrong — stop and
    move it, don't grind.
11. Don't abstract before the third *genuinely-same* call site. Duplication beats the
    wrong abstraction. Plain beats clever at equal correctness.

**Before "done":**
12. Adversarial pass, out loud: "what input makes this wrong?"
13. Name one downstream consequence of this change succeeding; check that one thing.
14. Invariant sweep: state one thing that must be true here; look for evidence it
    isn't.
15. Verify by *driving the real flow* end-to-end — not by typecheck, not by a green
    test alone. Spot-check any claim you got secondhand.

**Know your ceiling:** these steps recover the constraints you *think to write down*.
They will not surface the bug that only appears from three distant subsystems at once,
the anomaly nobody flagged, or the third-order consequence. On wide-radius or
genuinely novel work, escalate — say what you can't hold, and hand it up.
