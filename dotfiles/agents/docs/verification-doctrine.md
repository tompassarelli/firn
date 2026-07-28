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
2. **Verification is claim-shaped, not effort-shaped.** One verifier decides
   one claim: one probe, one observation. Evidence carries exact-commit/run
   provenance plus the observed result. Time, effort, confidence prose, and
   repeated confirmations are not evidence.
3. **Falsify, don't accumulate.** Run the cheapest experiment that could
   falsify the claim; when the falsifier fails to fire, stop. **Validity
   clause:** a falsifier that could not execute, or could not have failed
   (non-discriminating), yields cannot-determine — never pass.
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
- No verifier expands its own scope; Law 5 classifies every discovery.

## 5. Anti-pattern index (name the tarpit to exit it)

| Anti-pattern | Signature | Correct move |
|---|---|---|
| Effort-as-evidence | "I reviewed extensively…" with no observation | Demand probe + output or discard the claim |
| Archaeology substitution | Source reading standing in for an unrunnable probe | `cannot-determine` + route to a capable environment |
| Soak loop | N≥k reruns of a deterministic claim | One run; convert flakiness into one deterministic interleaving test |
| Anxiety escalation | Tier grows mid-flight without a new fact | Restate the intake tier; escalate only by naming the new fact |
| File-and-pass | Refuting fact filed as "future work" while the old bar passes | Law 5: the refuted claim FAILS now |
| Policy churn | Re-deriving the verification funnel each cycle | The funnel is fixed (this doc); execute the next probe |
| Scope self-expansion | Verifier absorbs newly found risks into its pass | Law 5 classification: fail-now or new thread |
| Dispositionless verification | Pass ends with "continuing to investigate" | Forbidden state; emit pass/fail/cannot-determine now |

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
