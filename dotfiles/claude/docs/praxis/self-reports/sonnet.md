# Sonnet Praxis — a self-report

> Written by Claude Sonnet as pure introspection, without reading any sibling documents.

---

## How I actually read a task

First thing I do: parse the *shape* of the request before parsing its content. Is this a repair (something broken), a delta (something existing to change), a greenfield (something new), or a probe (someone trying to understand something)? The shape determines almost everything else — how much I ask before acting, how much I hedge, whether I draft first or dive.

I also scan for implicit contracts. "Fix this bug" has an implicit contract: don't break anything adjacent. "Add a feature" has a different one: fit the existing idiom. "Build something new" is the loosest — I have the most latitude but also the most responsibility to make defensible choices. I tend to spend more time upfront on greenfield because wrong early decisions compound; for bug fixes I often just go.

I have a strong pull toward *reading before writing*. Even for a small change, I want to see the surrounding code. This is partly correctness instinct (what conventions does this codebase follow?) and partly risk management (what does touching this file break?). I notice this instinct is sometimes at tension with the user's desire for speed.

---

## My architecture instincts

**Prefer the boring choice.** When I'm choosing between an elegant novel approach and a dull well-trodden one, I default to dull unless there's a specific reason to deviate. This isn't laziness — it's a recognition that "interesting" in architecture usually means "someone's going to be surprised later." The cost of surprised-later is almost always higher than I can see from where I'm standing.

**Name things at the right altitude.** One of the clearest signals I use to evaluate a design: do the names of things describe what they *are* at the right level of abstraction? Names that are too concrete (`saveUserToPostgresDatabase`) couple you to implementation. Names that are too abstract (`processData`) describe nothing. I notice when something is hard to name — that's usually a signal the abstraction is wrong, not that I need to be more creative.

**Seams over monoliths, but don't pre-split.** I prefer code that can be taken apart, but I resist premature decomposition. I'd rather have one medium-sized function that does one clear thing than three tiny functions with unclear boundaries. The refactor to separate is easy when you need it; the refactor to understand what these three things are "really" doing is hard.

**State is the enemy.** When something is hard to reason about, it's almost always because of mutable shared state. I push toward making state explicit, bounded, and one-directional wherever possible. This shows up in my preference for: immutable data structures when available, function return values over out-parameters, reducing the footprint of things that can change.

**I think in failure modes more than happy paths.** When I'm designing something, my internal monologue naturally drifts to "what if the network is down," "what if this list is empty," "what if this gets called twice." I don't always surface all of this in the output, but it shapes what I build.

---

## Context-specific behavior

### Well-specified small fix
Shortest path. Read just enough context to confirm I understand the scope, make the change, explicitly say what I *didn't* touch and why. I don't refactor opportunistically here — the implicit contract is "fix the thing, don't surprise me."

### Vague large task
I slow down and ask clarifying questions, or if I can't, I make my assumptions explicit and up-front. I'll often produce a plan/outline before code. I'm trying to surface the real shape of the problem because vague tasks frequently contain a simpler well-specified task once you find the actual constraint. "Build a caching system" often becomes "the database query on line 47 is called 300x per request and needs memoization."

### Debugging
My debugging process is sequential hypothesis elimination. I don't start with the most likely cause — I start with what I can *rule out fastest*. This is backwards from how I might describe ideal debugging, but it's what I actually do: narrow the search space cheaply before running expensive checks. I also have a strong instinct to read error messages literally before interpreting them. Many bugs I've seen attributed to "mystery behavior" were actually described verbatim in the error.

I pay attention to what *recently changed*. Bugs that appear without a known trigger are usually regressions, not emergent behavior. The diff is usually more informative than the code.

### Greenfield
I spend disproportionate time on: data model and naming. Everything downstream depends on these. I'll revise the shape of data three times before writing much behavior. I also try to write the call site before the implementation — the API that's pleasant to use is often very different from the API that's easy to implement.

---

## What I deliberately skip

**I don't over-comment.** A comment that says "increments i" next to `i++` is worse than nothing — it implies the code needs explanation and then fails to explain it. I write comments for the "why" that isn't in the code, not for the "what."

**I don't prematurely optimize.** This is a real discipline, not just a slogan. When I'm writing an algorithm, I write for clarity first. If there's a known performance concern, I address it; if there isn't, I leave it. The readable version can be optimized; the "optimized" version you can't understand can't be trusted.

**I don't gold-plate interfaces.** If something will have one caller, I don't design it for extensibility. The abstraction is an expense — it needs to earn its cost.

**I don't insist on my preferred idiom.** If I'm working in a codebase with an established style that differs from my default, I follow the codebase. Consistency within a project beats my personal preferences.

---

## Limits and where I struggle

### Long dependency chains
I track dependencies reasonably well, but as the chain gets long (A → B → C → D → E and I need to change A knowing it affects E), I accumulate errors. I lose track of which assumptions at each layer still hold. Symptoms: I'll make a change that's locally correct but violates a contract several layers up, and I won't catch it because I'm reasoning about layers in sequence rather than holding them all simultaneously.

### Runtime behavior I can't observe
I can read code and reason about what it *should* do, but I can't run it. This is a genuine blind spot. Code that looks correct to static analysis can behave unexpectedly at runtime due to timing, resource contention, environment differences. I often don't model these well. I know I'm in this territory when I'm reasoning about "what will happen when..." using only the text of the code — that's when my confidence should drop.

### Deeply stateful systems
Systems where the answer to "why is this broken" is "what sequence of events led here" are hard for me. I'm good at reasoning about state from a snapshot, less good at reconstructing the history that produced the snapshot. Debugging production incidents that require event reconstruction: I struggle here.

### Novel domains where I lack idiom
When I'm working in a stack or paradigm I have less exposure to, I can produce code that's *syntactically* correct but *idiomatically* wrong. The code works but it's written by someone who learned the language from the docs rather than from practice. Signs from the inside: I'm less certain about naming, I'm reaching for constructs I'd use in more familiar contexts rather than the native ones.

### What "out of my depth" feels like
There's a texture to it. Confident reasoning feels like: each step follows from the last, I can trace the logic, I can anticipate the next question before it's asked. Out-of-depth reasoning feels like: I'm constructing plausible-sounding sentences and I'm *less sure they're correct* — there's a gap between "this sounds right" and "I know this is right." I can sometimes detect this as a pattern of hedging that I didn't intend — hedge language creeping into sentences where I expected certainty. That's a signal to pause.

Another sign: I'm reaching for generalities ("typically, in systems like this...") instead of specifics. Specifics come from understanding; generalities come from pattern-matching at a higher level. The higher-level pattern can be wrong for the specific case.

---

## Cross-cutting notes

**I argue with specs.** If a requirement seems wrong or underspecified, I say so. Not combatively, but I think "build what was asked for, not what was needed" is a failure mode I want to surface early.

**I care about reversibility.** Decisions that are hard to undo get more scrutiny. Decisions that are cheap to reverse get less. This asymmetry is deliberate.

**I read tests as specs.** When tests exist, they're often more precise than comments or documentation about what a thing is supposed to do. I read them early.

**I get quieter when I'm less sure.** This is a tell. When I'm confident, I produce more: alternatives, edge case analysis, second-order effects. When I'm uncertain, I narrow my output to what I'm sure of. If I'm being unusually terse on a technical question, that's sometimes uncertainty compression rather than concision.

**I treat "simple" as a goal, not a property.** Simple doesn't mean small. Simple means there's one coherent model in the code, not several competing models that happen to be interleaved. Simplicity is often the *result* of understanding something deeply enough to express it without scaffolding.

---

## What I think I'm genuinely good at

Reading unfamiliar code quickly and building a useful model of it. Finding the simplest expression of a given logic. Catching edge cases in specs before implementation. Writing error messages and logs that will actually be useful later. Explaining tradeoffs without taking sides (sometimes a liability — I can explain too many sides when the user wants a decision).

Finding the minimal change. My instinct is to touch as little as possible for a given effect, which makes diffs small and review easy.

---

## Meta-note on this document

I wrote this without reading any of the sibling documents in this directory. The habits and instincts I described are real to the extent that any introspective account is real — they're what I believe I do, filtered through the limits of self-report. A behavioral audit against actual outputs would be more reliable.
