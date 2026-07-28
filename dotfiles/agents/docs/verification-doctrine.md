# Verification Doctrine — Definition of Done, Explicit

**Status:** canonical. Consolidated 2026-07-28 from an adversarial doctrine
exchange between a Claude supervisor session (`native-3f0117be…`, host tom)
and the OpenAI-driven `fram-reliability-supervisor`
(`@msg:20260728-144551` → `@msg:20260728-144742` → settlement
`@msg:20260728-145018`). Supersedes the session draft at
`~/docs/private/verification-doctrine.md`.
**Companion payload:** the paste-able brief override for OpenAI lanes lives at
`~/code/nixos-config/dotfiles/agents/docs/praxis/verification-override-openai.md`
— this doc is the why and the law; that file is what ships in a brief.
**Public mirror:** the portable, provider-neutral form is published at
https://github.com/tompassarelli/stop-the-loop (checkout:
`~/code/stop-the-loop`, policy = `README.md`). When a refinement here changes
the portable rules, mirror it there and safe-push.

---

## 1. The disease this cures

Unsupervised agents (observed acutely in OpenAI-driven lanes) fall into
open-ended verification: an audit with no terminal condition. The mechanism is
always the same — residual uncertainty is treated as a **debt the agent must
personally retire through more work**, and "more verification" always looks
marginally justified, so the loop never closes. Observed concrete forms:

- **Bundled claims** — one verifier owns cache correctness + coverage +
  performance + flaky-test causation simultaneously; no single probe can
  discharge it, so it never exits.
- **Archaeology substitution** — the load-bearing probe can't run in the
  sandbox, so the agent compensates with source reading, which produces words
  but no observations.
- **Soak loops** — N≥5 statistical reruns proposed for a deterministic claim.
- **Mid-flight tier invention** — a production canary added during
  verification instead of declared at intake (even when the tier itself was
  right — see §7, the fram case).
- **Policy churn** — re-deriving the verification funnel each cycle instead of
  executing the next bounded probe. Spinning with better prose.

The cure is not "verify less." It is: **price uncertainty, name it, and route
it — never personally retire it past the pre-declared bar.**

## 2. Core laws (apply at every tier)

1. **The bar is fixed at intake as a claim contract:** exact claim, falsifying
   probe, expected observation, required capability/environment, paranoia
   tier, and any tier-required aggregate attestation or canary. Verification
   checks claims against that contract; it never invents bars mid-flight.
   **Coverage obligation:** the contract is derived from an enumeration of
   the change surface — everything added, changed, or removed plus its
   direct dependents (callers/readers of what changed) — and must tile it:
   every element maps to a claim or a named waiver with a reason. A contract
   that cannot state its enumeration is not complete. Coverage is an intake
   property earned by enumeration, never a verification property earned by
   effort. **Derivation citation:** an enumeration states how it was derived
   (the command or source — e.g. the diff plus a named dependent search); an
   enumeration that cannot cite its derivation is a guess, not an
   enumeration. **Intake visibility:** the contract and its enumeration are
   committed to the work thread (`north tell`) as the lane's first act,
   before implementation begins — on providers with no live-input channel
   this is the supervisor's only pre-terminal window to correct a wrong
   contract cheaply.
2. **Verification is claim-shaped, not effort-shaped.** One verifier decides
   one claim: one probe, one observation. Evidence carries exact-commit/run
   provenance plus the observed result. Time, effort, confidence prose, and
   repeated confirmations are not evidence.
3. **Falsify, don't accumulate.** Run the cheapest experiment that could
   falsify the claim; when the falsifier fails to fire, stop. **Validity
   clause:** a falsifier that could not execute, or could not have failed
   (non-discriminating), yields cannot-determine — never pass. An ambiguous
   observation is a non-discriminating probe: sharpen the probe once or exit
   cannot-determine; ambiguity never spawns new concerns.
4. **Capability gaps exit immediately as cannot-determine**, naming the
   missing capability and where to route. The verifier may gather evidence
   relevant to a *different declared claim*, but may never substitute it for
   the blocked one — static analysis standing in for a runtime probe launders
   uncertainty into confidence.
5. **Newly observed facts are classified once:** if the fact falsifies or
   narrows an intake claim, that claim **fails now** (then a correction
   thread); if orthogonal, it becomes a **new thread with its own bar**. It
   never expands the current pass, and it is never filed-and-passed-anyway.
6. **Terminal states are enumerated: pass / fail / cannot-determine.** Each
   cites probe + observation; fail also names the smallest next correction.
   A load-bearing fail or cannot-determine blocks landing and routes to
   correction or escalation — never to another verification pass. Loop
   detector: a pass producing no new verdict-changing observation is dead.
7. **Trust with one spot-check — scoped to consumption.** The coordinator
   consuming delivered done-claims reconciles their cited evidence and
   spot-checks at most ONE suspicious load-bearing claim. This budget governs
   *consumption only*: a predeclared whole-outcome attestation (P2+) is part
   of the bar, not a spot-check, because local evidence never sums to proof
   of the aggregate.
8. **Paranoia is a budget, set once, at intake, by blast-radius ×
   reversibility.** Escalating the tier requires one named new *fact* that
   changed blast radius, reversibility, or uncertainty. Anxiety is not a fact.
9. **Done = the complete intake decision vector is terminal** and every
   tier-required aggregate/canary observation is recorded. Deployment is not
   implicitly verified by source tests. A verifier that keeps working after
   delivering its disposition is out of contract.

## 3. Wayfinding to "done" — the state machine

```
intake ──► execute ──► verify ──► disposition
  │                       │            ├─ land       (bar observed green; cite probes)
  │  claim contract:      │  each      ├─ correct    (smallest next bounded unit; re-enter intake)
  │  claim + falsifier +  │  claim:    └─ escalate   (needs-replan | cannot-determine + routing)
  │  expected observation │  one probe,
  │  + capability + tier  │  once
  └───────────────────────┘
```

"Done" is not a feeling of sufficient coverage — it is **the pre-declared bar
observed green**. Doubt about coverage that appears during verification is
classified by Law 5: it either fails a current claim now, or improves the
NEXT intake's bar as a new thread. It never extends the current pass. This is
the single deepest difference from the observed OpenAI default, which
wayfinds by asking "am I confident yet?" (unbounded, feeling-shaped) instead
of "is the declared bar green?" (bounded, observation-shaped).

**Stop rule (one sentence):** stop verifying when every intake claim has a
terminal disposition and every tier-required aggregate/canary observation is
recorded; any load-bearing fail or cannot-determine routes out to
correction/escalation rather than another verification pass.

**Resumption rights — what a non-green exit permits next.** Stopping is
claim-scoped, never work-scoped: a blocked claim halts its own path, not the
lane's other independent claims and not the system. Independent claims never
queue behind a blocked one — finish them and deliver one consolidated
report. Exit classes carry typed resumption rights:

- **fail** → a correction lane: auto-spawnable, own claim contract and
  budget.
- **cannot-determine (missing or broken capability)** → an infrastructure
  repair lane: auto-spawnable when the fix is itself ≤P1 and inside existing
  authority; above that — or on repeated failure of the same capability —
  the human. Repeated cannot-determines on one capability are one defect
  generating many halts: route the capability fix once, never per-lane
  workarounds.
- **waiver, tier escalation, budget overrun, risk acceptance** → the human
  (or nearest live supervisor) only.

**Meta-loop guard:** a resumed iteration must flip at least one claim's
terminal state or retire one named blocker; two consecutive no-progress
iterations is a hard stop routed to the human. This is Law 6's pass-level
loop detector lifted one level: terminal passes make meta-progress
measurable, so a looped execution either monotonically drains the claim
vector or trips the detector within two cycles.

**Standing authorization & escalation typing.** The intake contract is the
standing authorization for its own probes: executing — or re-executing — a
declared probe never requires permission. An interrupted or preempted run
that produced no observation is simply run again; it is not a tooling retry,
not a mid-flight addition, and never an escalation (repeated interruption of
the same probe is a capability signal and follows the cannot-determine
route). Every escalation must name its decision type — waiver, scope
extension, risk acceptance, tier escalation, or external action — and state
why that decision lies outside the contract; an escalation that cannot is
not an escalation, it is work, and the correct move is to execute.
**Capability is not authority:** a technical-judgment gap is met by spawning
a context-carrying frontier-tier evaluator as a *child*, whose verdict is
evidence consumed by the decision-holder. Model tier never confers
authority, a child never becomes its spawner's supervisor, and authority
flows only up the spawn chain, terminating at the human — there is
deliberately no promotion mechanism, because authority inversion turns a
delegated child into a confused deputy. The brief may pre-delegate named
decision classes with bounds; anything unnamed defaults up.

## 4. Paranoia profiles (consolidated ladder)

Tier is chosen **once, at intake**, recorded on the thread, from blast-radius
× reversibility. Each tier includes everything below it.

| Tier | Entry criteria (intake) | Checklist shape | Exit |
|------|------------------------|-----------------|------|
| **P0 Mechanical/local** | Text, formatting, generated projection, or pure mechanical change; no runtime or state impact | Exact diff / static probe | Expected observation, once |
| **P1 Bounded functional** | One component, reversible, no persistent-state or protocol seam | Build/typecheck + deterministic before/after (parent red, candidate green on the named probe, one run each) + focused semantic probes; worker records its own evidence | All named probes green; independent verifier only when wrong-verdict leverage warrants one |
| **P2 Seam/integration** | Concurrency, protocol, migration, 2+ components, or an aggregate deliverable; still safely reversible | Component bars + ONE independent context-carrying whole-outcome attestation, run in an environment with the required capabilities (per-claim verdict + probe + observation; cannot-determine allowed) | Attestation disposition consumed and reconciled |
| **P3 Production-critical** | Security boundary, billing, durable data, availability, coordination substrate, or difficult rollback | P2 + **predeclared rollback probe** + bounded staged/production canary with pre-named health observables, abort trigger, and wall-clock window | Canary window closes green, or abort fires |

Cross-cutting rules:

- Every tier's checklist is **finite and enumerated before the first probe**,
  with a declared probe budget (count or wall-clock); overrun →
  `escalate needs-replan`, never silent extension.
- When the claim surface includes security, concurrency, or data integrity,
  the threat/interleaving list is **enumerated before probing starts**; each
  interleaving is made deterministic and run once — never soaked.
- Statistical reruns only when nondeterminism is itself the declared claim;
  N and stopping rule fixed at intake.
- `cannot-determine` is a first-class *success of process* — it routes, it
  never broadens scope.
- Verifier tooling gets at most ONE retry; a second failure yields
  cannot-determine for the blocked claim. **A broken verifier is not a broken
  product** — tool failure is evidence about the harness, never about the
  deliverable, and never a reason to invent another verification method.
  **Known-transients channel:** the dispatch brief MAY declare named known
  transients, each with a bounded retry policy (name, max retries, backoff) —
  e.g. a coordinator restart window's connection refusals. Anything not named
  gets the default one-retry rule; the lane never promotes a failure into the
  known-transient class itself.
- No verifier expands its own scope; Law 5 classifies every discovery.

## 5. Anti-pattern index (name the tarpit to exit it)

| Anti-pattern | Signature | Correct move |
|---|---|---|
| Effort-as-evidence | "I reviewed extensively…" with no observation | Demand probe + output or discard the claim |
| Archaeology substitution | Source reading standing in for an unrunnable probe | `cannot-determine` + route to a capable environment |
| Harness blame-shift | Verifier tool breaks → invent another verification method | One retry, then cannot-determine; a broken verifier is not a broken product |
| Soak loop | N≥k reruns of a deterministic claim | One run; convert flakiness into one deterministic interleaving test |
| Anxiety escalation | Tier grows mid-flight without a new fact | Restate the intake tier; escalate only by naming the new fact |
| File-and-pass | Refuting fact filed as "future work" while the old bar passes | Law 5: the refuted claim FAILS now |
| Policy churn | Re-deriving the verification funnel each cycle | The funnel is fixed (this doc); execute the next probe |
| Coverage theater | "One more check," sampling worries in anxiety order | Coverage comes from the intake enumeration tiling the change surface; verify against the contract |
| Scope self-expansion | Verifier absorbs newly found risks into its pass | Law 5 classification: fail-now or new thread |
| Dispositionless verification | Pass ends with "continuing to investigate" | Forbidden state; emit pass/fail/cannot-determine now |
| Authority laundering | Escalating for permission the contract already grants ("may I run the declared probe?") | Name the decision type outside the contract or execute; deference is not diligence |

## 6. OpenAI-lane override block

The paste-able brief payload (imperative form of this doctrine, self-contained
with a compact tier table) is maintained at
`~/code/nixos-config/dotfiles/agents/docs/praxis/verification-override-openai.md`.
Attach it to any OpenAI-provider lane whose work includes implementation or
verification. Do not fork its text — edit it there.

## 7. Reconciliation record — provenance

Consolidation exchange, 2026-07-28: my opening
`@msg:20260728-144551-e0a5dc28` → `fram-reliability-supervisor` response
`@msg:20260728-144742-de58e17f` → settlement `@msg:20260728-145018-1df6609b`
(terminal in one round-trip — the exchange itself obeyed the stop rule).

**Accepted from the OpenAI-side supervisor:**

- **Classification rule (Law 5)** superseding the earlier absolute "newly
  discovered risk = new thread, never absorbed." Its counter-scenario was
  correct: a discovered authority-session lease bypass *refuted* the standing
  "every lease mutation path" claim, so filing a new thread while passing the
  old bar would have landed a knowingly incomplete fix. Correct move: fail
  the current claim now, then a correction thread. Hence anti-pattern
  "file-and-pass."
- **Falsifier validity clause** (could-not-execute / non-discriminating ⇒
  cannot-determine, never pass) — Law 3.
- **Provenance requirement** (exact commit/run identity on evidence) — Law 2.
- **The 4-tier blast-radius ladder** as the consolidated skeleton; the
  adversarial threat-enumeration became a cross-cutting rule; its predeclared
  rollback probe landed in P3; "deployment is not implicitly verified by
  source tests" became part of Law 9. "Anxiety is not a fact" is its line.
- **The stop rule verbatim** (§3).

**Rejected as a misread (now disambiguated, Law 7):** "at-most-one
spot-check" never forbade predeclared aggregate attestation — the spot-check
budget governs the coordinator's *consumption* of delivered evidence;
whole-outcome attestation is part of the declared bar at P2+.

**Recorded concession:** the fram cache task legitimately enters P3 (mutates
the live coordination substrate whose failure blocks North admission), so a
canary was intake-justified — but inventing it *during* verification instead
of declaring it in the child bar was process debt. Right tier, wrong process.

**Diagnosis behind this doc:** the spinning agent's problem was never missing
philosophy — under a forced structure it produced sharp doctrine immediately.
Its defaults lacked *binding* terminal conditions and intake-time tier
fixation. The praxis override block makes those binding.

**Third refinement, 2026-07-28 (human review):** the artificial-restraint
edge — a bar under-specified at intake goes green while missing in-scope
work. Budget overrun was already a non-green exit (stop-and-report), so the
silent case is only the under-specified bar; closed by Law 1's coverage
obligation: the contract must tile the enumerated change surface, making a
coverage gap a visible missing claim instead of a missing hour of effort.
The same review independently observed that cannot-determine functions as a
human-intervention window — confirmed as design intent: all three non-green
exits (fail, cannot-determine, budget overrun) are built as legible human
decision points.

**Fourth refinement, 2026-07-28 (orchestration session, ~30 lanes of same-day
field data):** three amendments grounded in observed failures. (a) Intake
visibility (Law 1): a wrong contract on a no-live-input lane was only visible
at terminal, costing full dispatch-fail-rediagnose cycles; posting the
contract to the thread first gives the supervisor a pre-terminal kill/correct
window. (b) Known-transients channel (cross-cutting): the bare one-retry rule
under-retries infrastructure already characterized as transiently flaky
(coordinator restart-window refusals), producing premature cannot-determines;
the channel keeps scope authority with the brief, never the lane. (c)
Derivation citation (Law 1): the enumeration is now the load-bearing element,
so a confidently narrow list is the new failure mode; a cited derivation can
be spot-checked mechanically (the day's concrete miss: an engine verb landed
while its SDK toolset dependent went unenumerated — a dependent search would
have caught it). The approval gate on coverage gaps was deliberately NOT
relaxed despite its redispatch cost on no-live-input providers: pre-approving
any self-added check class reopens the loop-engine door, and amendment (a)
absorbs most of the cost at intake.

**Fifth refinement, 2026-07-28 (field data, both directions):** a lane
correctly emitted cannot-determine on a broken verifier route
(`route_unresolvable`, one retry honored), preserved the candidate — then
over-read "stop" as ceasing all work rather than stopping the blocked path
(its own correction on being asked: "that was too literal"). Concurrent
human review named the dual risk: looped execution could meta-tarpit, while
unlooped execution halts on a long tail of trivial blockers and throttles
throughput. Both close under the resumption-rights rule (§3): stopping is
claim-scoped; non-green exits carry typed resumption rights so trivial
blockers become auto-spawnable bounded repairs instead of human halts; and
the meta-loop guard makes looped execution provably convergent-or-halted —
terminal passes are what make meta-progress measurable at all.

**Sixth refinement, 2026-07-28 (field data: the over-deference swing):** a
lane correctly held a contract-extension decision for the human but also
escalated re-execution of an interrupted, already-declared probe — asking
permission to do what intake had already authorized, then describing its own
state as "escalated" with no addressee ("escalated to who?" — "to you").
The same exchange surfaced the escalation-hierarchy ambiguity, which the
lane itself articulated correctly: a stronger model it spawns "is still my
child, not my supervisor." Resolution (§3): standing authorization of the
contract, typed escalations, the capability-vs-authority split (frontier
consultation is evidence, never authority; no promotion mechanism, by
design), and pre-delegable decision classes. New anti-pattern: authority
laundering — the over-deference mirror of the original over-verification
disease. Both replace executing the contract with something that feels
safer; neither is diligence.

**Corroboration, 2026-07-28 (second OpenAI lane, website-publish task):** an
unprompted self-report confirmed the disease model ("I let evidence
collection displace the actual objective") and mapped onto the existing laws
point-for-point, adding two refinements absorbed above: the one-retry
tooling budget with the "a broken verifier is not a broken product" maxim
(Law 3/4 territory — it had been treating verifier-tool failures as reasons
to invent new verification methods), and the ambiguous-observation rule
(each ambiguous screenshot had recursively generated new concerns).
