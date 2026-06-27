# Ultracode vs. lodestar+fleet+lodestar-web — does the override deliver?

## Verdict (blunt, up front)

**In the snapshot this report documents, the override is not switched on, so it delivers nothing.** Three independent facts establish this:

1. **The guard is OFF.** The sentinel `~/.claude/fleet-guard.off` exists (0-byte, Jun 24 23:25), so `fleet-protocol-guard.sh` exits 0 — raw `Agent`/`Workflow` is **ALLOWED**, not blocked. The fleet protocol is not being enforced.
2. **lodestar `:7977` is DOWN.** `lodestar doctor` reports `[DOWN] no coordinator on 127.0.0.1:7977 — writes won't serialize`. No capture, no `tell`, no work queue.
3. **lodestar-web `:8088` is DOWN.** No `bridge.clj` process; the port refuses connections. Last fleet activity was **Jun 25**.

Net: as it sits, **the user is running plain vanilla ultracode** (`effortLevel="xhigh"` + Workflow allowed) — the lodestar/fleet/lodestar-web override is dormant, unbooted, and unenforced. "Does the override deliver?" → *currently it delivers nothing, because it is not turned on.* Everything below evaluates what it **would** deliver if booted, and whether booting it is worth the cost.

The deeper answer, once booted: the override buys exactly **one** thing Anthropic structurally cannot match today — **cross-session persistence** (role-addressable agents standing at ~0 idle cost, coordination state durable in an append-only claim log). On every *deterministic orchestration primitive* — fan-out, barrier/join, synthesis, schema-validated output, judge panel — plain Workflow wins outright. And the persistence it buys is, on the evidence gathered here, **barely used** (see ROI, below): the $149 / 89-run / 24-agent activity reads as a batch of dogfood demos, not recurring real work. So the honest framing is not "keep and improve" vs. "rip out" but **a hybrid**: keep `xhigh` Workflow as the default engine for deterministic fan-out, and boot the fleet only for the narrow case that actually needs cross-session persistent coordination — a case that, for this user, is currently close to empty.

## Executive summary

The override is worth keeping for one reason Anthropic structurally cannot match today: **persistence**. Anthropic's dynamic workflows are session-scoped — exit Claude Code mid-run and "the next session starts the workflow fresh." The lodestar+fleet substrate keeps role-addressable agents standing at ~0 idle token cost, with coordination state durable in an append-only claim log across sessions. That is real, exercised infrastructure on disk (24 agents booted, 89 `claude` runs, ~$149 spend), **but — see the ROI section — that activity is batch-shaped dogfooding, not a recurring-work habit, so the persistence it provides is currently a capability in search of a use**. **The single biggest capability gap is that the fleet has none of Workflow's deterministic orchestration primitives** — no fan-out, no barrier/join, no automatic synthesis, no schema-validated output, no built-in judge panel. Every one of those is a hand-written `msg-cli send` and an eyeball-the-inbox roll-up today. **The single highest-leverage next move — and a hard prerequisite for everything else — is to make the daemons managed services** (systemd user units in the nixos lodestar module): right now the lodestar `:7977` coordinator is DOWN, lodestar-web `:8088` is dead, and the guard is OFF, so the entire "persistent, always-on, observable, enforced" pitch only holds while someone remembers to boot and arm it by hand. Persistence you have to manually start is not persistence.

## The override mechanism

Two **independent** levers, not one coupled system. The task premise that a hook injects an "ultracode is on/off" context is **false** — effort has zero runtime surfacing.

**Lever 1 — effort, a single declarative key.** `~/code/nixos-config/dotfiles/claude/settings.json:91` sets `effortLevel` to the literal string `"xhigh"`. That is the entire override surface for effort — no hook, no env var, no sentinel. Companion keys in the same file: `"alwaysThinkingEnabled": true` (line 90) and `"skipWorkflowUsageWarning": true` (line 98). `~/.claude/settings.json` is a symlink to this committed file, so the repo copy IS the live source of truth; `~/.claude/settings.local.json` exists but carries no effort key, so it does not override.

> Interpretation vs. fact: per Anthropic's own docs, the API-accepted effort set is exactly `low|medium|high|xhigh|max`, and "ultracode" is a Claude-Code menu entry that maps to `xhigh` + standing workflow-orchestration consent — it is **not** a sixth API level. The repo only evidences the literal `effortLevel="xhigh"`. The "xhigh = the max/ultracode tier" framing is the researcher's label; the word "ultracode" appears nowhere in `settings.json`, and the harness-wide `effortLevel` key is a distinct mechanism from the `/code-review` skill's `ultra` argument.

**Lever 2 — the fleet-protocol guard, a separate PreToolUse hook.** Wired at `~/code/nixos-config/dotfiles/claude/settings.json:44-53` (matcher `Agent|Workflow`) to `~/code/nixos-config/dotfiles/claude/hooks/fleet-protocol-guard.sh`. Lines 36-37 are the gate (read `tool_name`, membership-test against `("Agent","Workflow")`); the `deny` verdict is emitted at lines 52-58. Two bypasses fire first: the global kill-switch env `CLAUDE_NO_AUTHORING_HOOKS` (line 17), or the per-machine sentinel `~/.claude/fleet-guard.off` (line 23 — `[ -f ... ] && exit 0`). The sentinel is toggled by `~/code/nixos-config/dotfiles/claude/hooks/fleet-guard-toggle.sh:11-18` via the `/fleet-guard` command: **off touches the sentinel = Agent/Workflow ALLOWED; on removes it = BLOCKED.**

**Latent contradiction.** `xhigh` wants Workflow fan-out, but the guard blocks raw `Workflow`. Today there is no live conflict because the guard is **OFF**: the sentinel `~/.claude/fleet-guard.off` exists (0-byte, Jun 24 23:25), so `fleet-protocol-guard.sh` exits 0 and Agent/Workflow is currently allowed. The contradiction only materializes if someone runs `/fleet-guard on` while `effortLevel` stays `xhigh` — then ultracode Workflow orchestration is silently denied with a generic "use lodestar" message and no hint that effort expected Workflow.

The only SessionStart hook is `~/code/nixos-config/dotfiles/claude/hooks/beagle-session-start.sh` (additionalContext assembled at line 72, injected at line 75) — it carries **Beagle authoring context only**, nothing about effort or ultracode. An agent cannot know it is running `xhigh`.

**Minimal lever to change defaults.** Edit `settings.json:91` — change `"xhigh"` to a lower tier or delete the key — then `./scripts/firn-build` (if sourced from `.bnix`) and commit. That single key is the whole effort surface. Because it is a committed nixos-config symlink, a "temporary" change is really a repo edit needing rebuild + commit; there is no per-session override path.

## Anthropic ultracode — the parity bar

This is the capability list any replacement must clear. **Verification is mixed, and the unverified half is flagged inline** so a skim-reader knows roughly half this parity bar is inference, not Anthropic-documented fact. Legend: **[DOC]** = corroborated by Anthropic's public docs (2026-06); **[INFER]** = uncited, inferred from the single hand-rolled "Build an orchestration mode" API example or from key names. The deferred caveats are consolidated under Open Questions.

- **[DOC] Dynamic workflows are GA** — Claude Code v2.1.154+, all paid plans + Anthropic API + Bedrock + Vertex + Foundry. A workflow is a JS script Claude writes; a runtime executes it in the background while the session stays responsive.
- **[DOC] Ultracode = `xhigh` + standing consent** to orchestrate. "Claude plans a workflow for each substantive task instead of waiting for you to ask." Session-scoped; reset with `/effort high`. One request can spawn several workflows in a row (understand → change → verify).
- **[DOC] Context discipline** — intermediate results live in **script variables**, not Claude's context: "the script holds the loop, the branching, and the intermediate results itself, so Claude's context holds only the final answer."
- **[DOC] Deterministic fan-out** — tens to hundreds of parallel subagents. Caps **[DOC]**: **≤16 concurrent** (fewer on low-core machines), **1,000 agents/run** hard cap. **[INFER]**: the exact `min(16,cores-2)` formula and the 4096-items/call cap are from the live spec only — not publicly documented.
- **[INFER] Orchestration primitives** (live spec, **not publicly documented** — inferred from one API example): `agent(prompt,{schema,model,effort,isolation,agentType})`, `pipeline(items,...stages)` no-barrier per-item streaming, `parallel(thunks)` barrier, `phase()`, `log()`, `budget`, nested `workflow()`. **Half the parity bar the fleet is measured against is this single bullet — treat its function signatures as inference.**
- **[DOC] Adversarial verify is first-class** — "independent agents adversarially review each other's findings before they're reported." The API "Build an orchestration mode" example implements a two-wave pattern (wave 2 = "try to REFUTE it; re-derive with bash").
- **[DOC] Cross-check + claim-voting** — bundled `/deep-research` fans out, cross-checks sources, votes per claim, filters non-surviving claims from a cited report.
- **[INFER] Schema-validated structured output with model retry** — `agent(...,{schema})` validating at the tool-call layer is **live-spec only**; the public API example only *approximates* it with a `report_findings` JSON tool.
- **[DOC] Script-as-artifact** — written under `~/.claude/projects/<session>`, readable/diffable/editable/re-runnable, savable as a `/<name>` command.
- **[DOC] `/workflows` TUI** — per-phase agent counts/tokens/elapsed, drill into any agent, pause/resume/stop/restart, save-as-command.

**Anthropic's own admitted gaps** (where a persistent fleet can win): resumability is **session-scoped only**; **no mid-run user input** (sign-off requires splitting into separate workflows); intermediate results vanish at run end (no durable memory/history); token cost is unbounded-by-design beyond the 16/1000 caps; subagents always run **acceptEdits** regardless of session permission mode; observability is **TUI-only and ephemeral**.

## The fleet substrate — lifecycle, roles, leases, and the honest capability matrix

**Three ports, three jurisdictions.** `:7977` = canonical lodestar work queue (durable thread/intent ledger). `:7978` = the fleet coordinator daemon (`cnf_coord_daemon.clj serve 7978 ~/code/fleet-data/claims.log`, cwd `~/code/fleet-coord`) — presence + roles + leases. `:8088` = lodestar-web lodestar web bridge.

**Everything is a claim.** The daemon stores `(subject predicate object)` triples and firehoses commits; it never routes. presence/msg/lease CLIs are typed projections of one claim graph. Writes use OCC (read `:version`, assert at base, retry 4× on reject).

**Lifecycle** (each step is a real command). SPAWN (`~/code/fleet-data/spawn-agent.sh <role>` mints a 12-char uuid, `setsid`-detaches `fleet-agent.sh`) → IDENTITY/REGISTRATION (`presence-cli identify`/`register`, acquiring a 10-min session-liveness lease, then `assign` per role) → ROLE/LEASE GATING (exclusive role does `:acquire-lease res=role:<slug>`; hold-zero-roles ⇒ self-abort `forget`+`exit 0`, `fleet-agent.sh:47-51`; a side heartbeat renews every 180s) → BOOT DRAIN (one `claude -p` reads recovery, drains inbox, acts, persists claims) → DORMANT LOOP (`fleet-listen.clj --once --ack` on the `:7978` push socket — **zero tokens, zero polling** until a commit matches scope `{uuid} ∪ {held roles} ∪ {"*"}`) → STEER (`msg-cli send` writes `@msg` claims; the agent wakes ONE `claude -p` turn — **picked up on the NEXT wake, no mid-run interrupt**) → WORK + FORCED REPORT (set focus, verify, `msg-cli send ... "DONE: … | <evidence>"` or `BLOCKED:`; going dormant without a report is a defined FAILURE) → OBSERVE (`presence-cli presence`, lodestar-web, `tail -f`) → STOP (`touch ~/code/fleet-data/stop-<uuid>`).

**Roles** are user-defined (`presence-cli define-role <slug> <exclusive|inclusive> "<title>"`), not a fixed enum. An agent's identity = the SET of roles it holds; you address a role and it routes to the current holder (agents fungible, roles the stable address). ~27 roles are defined in `~/code/fleet-data/claims.log` (fleet-commander, fram-engine, beagle-compiler, lodestar-web + fs-* workers, oakaudit-attest/falsify, readcell-1..4, etc.).

**Lease-gating.** Concurrency lives in the engine (`fram cnf_coord.clj` owns write-serialization + OCC + the lease primitive); apps express coordination as claims, never self-rolled locks. A lease is decided by the **coordinator's** clock. Liveness is **derived** — a dead agent's lease lapses and `online?` flips false on its own, with **no separate reaper** (the design's headline trick). The build mutex uses the same primitive plus a fencing token. The docs stress `driver` (`:7977` app-level intent) vs `lease` (`:7978` DB-level mutual exclusion) — never conflated.

### Capability matrix (the heart of this report)

| Capability | Anthropic Workflow | This fleet | Gap |
|---|---|---|---|
| Cross-session persistence | Session-scoped; run restarts fresh on exit | Standing dormant agents + durable claim log survive session end | **Fleet wins** |
| Idle cost | N/A (ephemeral) | ~0 tokens while dormant (push socket, no polling) | **Fleet wins** |
| Mid-run human steering | Forbidden ("no mid-run user input") | `msg-cli send`, consumed on next wake (not real-time, but possible) | **Fleet wins** (partial) |
| Role identity / leases | Every agent is a fresh ephemeral worker | Exclusive lease-gated roles; stable role addresses across runs | **Fleet wins** |
| Durable observability | TUI-only, ephemeral `/workflows` pane | presence roster + lodestar-web cockpit + claim history | **Fleet wins** (when running) |
| Deterministic fan-out (map N) | `parallel()`/`pipeline()`, ≤16 conc, 1000/run | None — hand-write N `msg-cli send` lines; nothing guarantees N start | **Anthropic wins** |
| Barrier / join / fan-in | `parallel()` barrier | None — supervisor eyeballs inboxes manually | **Anthropic wins** |
| Automatic synthesis / reduce | Built-in reduce stage | None — supervisor composes the roll-up by hand | **Anthropic wins** |
| Schema-validated structured output | `agent({schema})` + model retry | Freeform `DONE: <what> | <evidence>` strings; no validator | **Anthropic wins** |
| Adversarial verify / judge panel | First-class (two-wave); `/deep-research` voting | Convention only — oakaudit-attest/falsify roles hint, no structural gate | **Anthropic wins** |
| Context discipline (script holds intermediates) | Yes — context holds only final answer | No equivalent; each turn is a full `claude -p` | **Anthropic wins** |
| Loop-until-dry queue worker | Available pattern | Anti-loop by design ("one ping, one response"); needs hand-rolled outer loop | **Anthropic wins** |
| Delivery guarantee | Runtime-enforced | **Prompt-level only** — nothing structurally blocks dormant-without-report | **Anthropic wins** |
| Budget/depth governor | Hard 16/1000 caps | Prompt-level "don't fork-bomb"; cost recorded after the fact only | **Anthropic wins** |
| **Maintenance / operational burden** | **Zero** — managed, hosted infra; nothing to boot, patch, or babysit | **High** — hand-booted daemon SPOF (`:7977`/`:7978`/`:8088`), all DOWN now; `RUNBOOK.md` SS6 is a ghost-hunt of orphan-process cleanup one-liners | **Anthropic wins (heavily)** |
| **Security / permission blast-radius** | Bounded — subagents run `acceptEdits` (noted, auditable, single mode) | **Unbounded per agent** — each fleet agent `setsid`-spawns a full `claude -p` with its own, unexamined permission mode; N agents = N independent permission surfaces | **Anthropic wins** |

The pattern is stark: **the fleet wins on persistence/observability/identity; Anthropic wins on every deterministic orchestration primitive AND on the two axes that matter most for "should I run this at all" — operational burden and security blast-radius.**

**Rows are not equal — a raw tally misleads.** Counting cells gives ~10 Anthropic / 5 fleet, which on its own would read as "rip it out." But the rows carry very different weight, so here is an explicit (subjective) weighting rather than a flat count:

- **Decisive, high-weight (×3):** *Cross-session persistence* (the one thing Workflow structurally cannot do) for the fleet; *Maintenance burden* and *Security blast-radius* for Anthropic. On the high-weight rows it is **1 fleet vs. 2 Anthropic** — and the two Anthropic wins are "this thing is dead/unmanaged/unbounded right now," which is why the snapshot verdict is "delivers nothing."
- **Medium-weight (×2):** deterministic fan-out, barrier/join, synthesis, schema output, budget governor — **all Anthropic**, and collectively they *are* "ultracode's job."
- **Low-weight / situational (×1):** idle cost, mid-run steering, role identity, durable observability — mostly fleet, but only valuable once a *recurring multi-session workload* exists to amortize them.

So the honest read is **not** "they are equal-and-complementary." The fleet is a better *substrate*; Workflow is a better *engine* — but the guard makes them **mutually exclusive at runtime** (guard-on blocks `Workflow`; guard-off allows it but then the fleet protocol isn't enforced), so you do not get both for free in one session. The strategy the matrix actually points to is a **hybrid**: run `xhigh` Workflow as the default for deterministic fan-out (its winning half), and boot + arm the fleet *only* for the narrow cross-session-persistent-coordination case (its winning half), making the effort-aware guard (rec 5) the switch that arbitrates between the two modes instead of silently denying one. "Complementary" is only true if something lets them coexist — today nothing does.

**Operational caveats.** The four CLIs (presence/msg/fleet-listen/lease) exist in two locations — `~/code/beagle/.scratch/` and the canonical `~/code/lodestar/fleet/cli/` — **confirmed byte-identical** at read time. Scripts (`fleet-agent.sh:25`) and `~/code/fleet-data/RUNBOOK.md:19` both reference the lodestar copy; the **only** stale pointer is `~/code/lodestar/CLAUDE.md:19` (still names `beagle/.scratch`). The `:7978` daemon + `:8088` bridge are a manually-brought-up SPOF; `RUNBOOK.md` ships a whole SS6 ghost-hunt of orphan-cleanup one-liners precisely because the substrate accrues stranded OS processes (the lease-lapse handles liveness, not stranded `tail`/`fleet-listen` PIDs).

## Framescope — real value or aspirational?

**What it is.** A babashka + http-kit bridge plus a Cytoscape.js frontend. `~/code/lodestar/lodestar web/bin/lodestar-web [port]` daemonizes the bridge (`setsid`+`nohup`, fixing a bug where it died on shell exit) and serves `~/code/lodestar/lodestar web/web/` on `:8088`. The bridge (`~/code/lodestar/lodestar web/bridge/bridge.clj`) is the only component speaking the raw line-delimited-EDN TCP protocol; it federates four daemons by port (fleet `:7978`, code `:7979`, board/lodestar `:7977`, attention `:7980`) and exposes `/graph /presence /timetape /live /stream /steer /node /edge /retract /distill` (and `/schema`) at `bridge.clj:487`.

**Observability** is real and concrete: `/stream` (`ws-stream`, `rt.clj:236`) runs `tail -n 200 -f` on `~/code/fleet-data/agent-<uuid>.stream.jsonl` (the agent's `claude -p --output-format stream-json` trace) and pushes assistant text, thinking, tool calls/results, and a cost ticker to the browser — literally "watch it think." The left roster comes from `/presence`. **Steerability**: `/steer` POST calls `steer!` (`rt.clj:162`), which shells to `msg-cli.clj` to inject a message into a running/dormant agent's inbox.

**Has it delivered?** Partially, and intermittently. The fleet underneath was genuinely exercised: `~/code/fleet-data` holds **26 agent uuids (24 logged a BOOT), 89 `claude` runs totaling ~$149.04, 65 PINGED events**, and large real `stream.jsonl` traces (e.g. `agent-b2c4741f1470`: BOOT → PINGED by audit-lead → a 271s/$1.748 run → back to dormant, with genuine assistant/thinking/tool_result events). So the streams are real. **But lodestar-web is NOT running now** — no `bridge.clj` process, `:8088` refuses connections, last fleet activity Jun 25; it is launched manually on demand, not persistent infra.

### ROI — what did the $149 / 89 runs / 24 agents actually buy?

The activity proves the infrastructure *runs*; it does **not** prove the infrastructure *pays off*, and the report should not let the two be conflated. Converting activity → value:

- **Spend is trivial; that is not the point.** ~$149 of API spend over 89 runs is noise against the value of even one real deliverable. The question is not "was $149 wasted" — it is "did the *persistence* (the one thing this buys over plain Workflow) get used for recurring real work?"
- **The usage signature says demo, not habit.** The same batch-not-habit signature flagged for lodestar capture applies here and was not previously applied to the fleet: activity is **clustered, then silent**, last touch **Jun 25**, with the largest traces tied to *meta* work — auditing the fleet itself (`audit-lead`, `oakaudit-attest/falsify`) and building lodestar-web (the `fs-*` workers). That is the profile of **dogfooding the substrate**, not of a standing team doing recurring product work across sessions.
- **Persistence specifically appears unused.** The decisive fleet advantage is *cross-session* coordination. But the traces are individual ping→run→dormant cycles inside what look like single working sessions; there is no evidence of a thread of work *resumed by a standing role days later* — i.e. the exact capability persistence exists to provide. The agents stood at ~0 idle cost, but mostly nothing woke them.
- **Implication for the verdict.** The single justification carrying the whole "keep it" case — "persistence is worth it" — is **not yet demonstrated by the user's own usage**. The $149/89/24 figures are evidence the machine *works*, re-labeled here, honestly, as evidence it was *built and demoed*, not evidence it *earns its keep on recurring work*. Until a real recurring multi-session workload exists, the persistence ROI is speculative.

Two honest corrections to the earlier framing:

- **`steer!` does NOT swallow failures.** It returns `{:ok (zero? exit) :out <stdout+stderr>}`, which the `/steer` route serializes straight back to the UI — a failed send surfaces `:ok false` plus captured error text. The "fires the host process, failures swallowed" comment belongs to `run-distiller!` (the `/distill` route), not `steer!`. The real steer limitation is the **next-wake** delay, not silent no-op.
- The render→vision loop (the commander ingesting cockpit screenshots with its own vision) **is still aspirational**, blocked on absent chromium/playwright (thread `~/code/lodestar-data/threads/2026-06-22-231850-...`). Per `BRIEF.md:82`, **Tom (the human) is the agent's eyes** — "you can't see the render; he is your eyes" — and `@lodestar-web` coordinates with `@fleet-commander`, never Tom; the eyes-human and the commander are distinct.

Also stale: `bridge.bclj` `:file` annotations still point at `~/code/lodestar-web`, which no longer exists (source moved into `~/code/lodestar/lodestar web`).

Net: observability is **delivered and evidenced**; always-on infra and the vision loop are **not**.

## Lodestar as task management — and why capture isn't reflexive

**The claim model.** A thread is not a record — it's a bag of `(subject predicate object)` triples in one append-only log (`~/code/lodestar-data/claims.log`, ~5,538 lines). Identity is the `@id` subject; a node becomes a thread purely by having a `title`. There is **no `status` predicate** — lifecycle is **derived at read time** (`~/code/lodestar/docs/operating-manual.md:191-227`): committed = `committed` ∧ no `abandoned`; done = `outcome` present; canceled = `abandoned`; active = `driver` set now; blocked = a `depends_on` still non-terminal; dormant = committed ∧ not active ∧ not done. You never edit a status — you move lifecycle by **adding a fact**. Terminal/withdrawn predicates are declared via env in `~/code/lodestar/bin/lodestar:15-16`.

**The intended loop.** capture (thread minted committed-by-default, owner personal, **no driver at birth**) → persist (asserted through `:7977` into the log; `threads/*.md` is a regenerable projection) → surface (warm-daemon read projections: `ready`/`next`/`plate`/`agenda`/`blocked`/`leverage`/`needs-review`) → execute (`tell <id> driver @claude-code` activates; `clock start` opens a calibration session) → outcome (`tell <id> outcome "…"` derives done). Both `lodestar` and `fram` MCP servers are globally registered in `~/.claude.json`, so the **17** MCP tools (ready/next/plate/blocked/agenda/leverage/needs_review/validate/show/capture/tell/untell/clock_start/clock_stop/clock_status/clock_report/presentation) are present in every session. The nixos module `~/code/nixos-config/modules/lodestar/default.bnix` only puts the CLI on PATH.

**Why capture isn't reflexive.** The substrate is real (473 thread files, ~2 MB log, MCP wired globally) but the usage signature is **batch, not habit**: created_at histogram shows 69 captures on day one (a migration dump), 34/28/13 on other days, interspersed with multi-day zeros. The genuinely reflexive captures that exist (the 06-25 batch) are thin (title + provenance + committed, empty body) and all fired **while dogfooding a different app** — capture happens when an AI is already in a session about that thing, not as a standalone life habit. Concrete blockers:

- **The daemon is not a managed service.** `:7977` is **DOWN right now** — `lodestar doctor` reports `[DOWN] no coordinator on 127.0.0.1:7977 — writes won't serialize` and `[WARN] 9 file claim(s) not in the log … DEGRADED`. The remedy today is a **manual** `lodestar up` handshake. A capture target you must remember to boot will never be the default reflex.
- **The doctrine excludes trivial notes.** The manual sets a **low** bar ("Create one when a thought needs a stable shelf. The bar is low.") but explicitly **excludes** one-line notes ("call mom") and near-duplicates, and says "small things go in the body, not as new threads." (Earlier framing called this "actively raising the bar" — that overstates it; the manual's own tone is *low bar, but no trivia*.) Either way, it asks the user to **triage at capture time**, which is exactly the friction a frictionless inbox must not have.
- **No zero-friction global capture surface.** No `~/code/nixos-config/dotfiles/bin/` quick-capture script, no global hotkey, no phone/email path. You must be at the desk, in the right tool, with the daemon up.
- **Capture depends on AI judgment + the AI having read the manual.** The session behaviors (run doctor at start, match-thread-on-engagement) are AI *habits*, not automation; they fire only if the AI loads the manual and chooses to act.
- **Write-safety ceremony** (`tell`-not-`set`, never-export-under-concurrency, import-to-reconcile, the doctor handshake) makes the substrate feel fragile. The current 9 un-imported drift claims are that ceremony failing in practice.
- **The only GUI** (lodestar-web/lodestar web) is a claim-graph **visualizer**, not a capture inbox — no fast "+ add", no ambient daily dashboard. (Per `BRIEF.md`, lodestar-web's v1 hero is the fleet graph on `:7978`; `:7977` thread lifecycle-coloring is a v2 item — so the visualizer isn't even pointed at the life-OS graph yet.)

## End-to-end worked example — the full override loop on one task

The sections above evaluate each component in isolation. This traces **one concrete task through the entire override loop**, so the reader can judge whether the assembled system delivers — not just whether each part works alone. The task: *"Audit every `.bnix` module in nixos-config for stale `:file` annotations and fix them"* — chosen because it is fan-out-shaped (N modules) **and** plausibly multi-session (a finding parked, resumed later), so it touches both halves.

**Precondition (today this fails):** the loop assumes `:7977`, `:7978`, `:8088` up and the guard armed. In this snapshot all three daemons are DOWN and the guard is OFF, so step 0 is **`lodestar up` + boot the fleet coordinator + `lodestar-web` + `/fleet-guard on`** by hand. This is exactly the friction rec 1 removes; until then the trace below cannot start.

1. **Task arrives → `xhigh` plans.** Ultracode (`effortLevel="xhigh"`) sees a substantive task and plans an orchestration instead of doing it inline. *Decision point the guard arbitrates:* pure single-session fan-out → it would just use `Workflow` `parallel()` over the module list and finish in one run. Because this task is *also* meant to survive a session boundary, it routes to the fleet.
2. **Fleet spawn + role.** `~/code/fleet-data/spawn-agent.sh bnix-auditor` mints a uuid, `setsid`-detaches `fleet-agent.sh`; the agent `presence-cli identify/register`s, acquires the session-liveness lease, and `assign`s the `bnix-auditor` role.
3. **Lease + dormant.** The role is exclusive, so it `:acquire-lease res=role:bnix-auditor`; holding ≥1 role, it does **not** self-abort. It boot-drains its inbox, then drops into `fleet-listen.clj --once --ack` on the `:7978` push socket — **0 tokens, 0 polling** until a commit matches its scope.
4. **Steer.** The supervisor `msg-cli send`s `@msg` to the role: *"audit modules a–m; report stale `:file` paths."* The claim lands; the agent wakes **one** `claude -p` turn on its **next** wake (not a mid-run interrupt).
5. **Work + forced report.** The agent greps the modules, finds 3 stale annotations, and must emit `DONE: 3 stale :file in chrome/firefox/kanata | <evidence paths>` (or `BLOCKED:`). *Gap surfaced:* today nothing structurally enforces this (rec 3); the report is prompt-level only, and the `DONE` string is freeform with no schema (rec 4).
6. **lodestar capture / outcome.** The finding is captured as a lodestar thread via `:7977` (`capture` → committed draft), and on fix `tell <id> outcome "3 annotations corrected"` derives *done*. *This* is the multi-session payoff: if the session ends after step 5, the thread and the standing `bnix-auditor` role both survive, and the fix can be resumed tomorrow by the same role address — the one thing Workflow structurally cannot do. *Gap surfaced:* capture is not reflexive and `:7977` must be up (recs 1, 9, 10).
7. **lodestar-web observe.** Throughout, `:8088` streams the agent's `claude -p --output-format stream-json` trace (`tail -f` on `agent-<uuid>.stream.jsonl`) to the Cytoscape cockpit — assistant text, thinking, tool calls, cost ticker — and the presence roster shows `bnix-auditor` online. The human steers via the `/steer` button (→ `msg-cli`), surfacing the next-wake-delay limitation, not a silent no-op.

**What the trace shows:** the loop *does* compose end-to-end — but its delivered value over plain `Workflow` is **only step 6's persistence**, and every other step is either (a) a thing Workflow does better and atomically (steps 1, 5 fan-out/synthesis/schema) or (b) operational overhead Workflow doesn't have (steps 0, 2, 3, 7). For a *single-session* version of this task, steps 0/2/3/4/7 are pure tax. That is the worked-example form of the verdict: the assembled override earns its complexity **only** when step 6's cross-session resumption is actually exercised.

## Synthesis & recommendations

### The counterfactual first: should this exist at all?

Every recommendation below assumes *keep-and-improve*. An honest "is it worth it" has to state the null option just as plainly:

**The rip-it-out case is strong for the common path.** For the overwhelming majority of this user's tasks — "understand → change → verify" on one repo in one sitting — **plain `xhigh` Workflow wins outright**: it has the deterministic primitives (fan-out, barrier, synthesis, schema, judge panel), zero maintenance, a bounded permission model, and it is *already on and allowed* in this snapshot. For those tasks the fleet adds latency, operational burden, and a second permission surface for **no** capability the task needs. If the persistent-coordination case below never materializes, deleting the fleet wiring (or leaving it permanently unbooted, which is the de-facto state today) costs the user nothing and removes a SPOF.

**The fleet pays off only in one narrow case:** work that is **(a) genuinely multi-session** — a unit of work picked up, parked, and resumed days later by a stable role — **and (b) coordinated across several concurrent agents** that must hold exclusive leases and survive session exit. Both conditions must hold; either alone is better served by Workflow (single-session fan-out) or a plain TODO/notes file (solo durable memory).

**How narrow is that for *this* user?** On the gathered evidence, **close to empty right now.** The fleet's own activity (ROI section) is batch dogfooding with no resumed-days-later thread; lodestar capture (next section) is batch-not-habit with the daemon down; the heaviest real usage was building/auditing the substrate itself. So the population of tasks that *actually* exercise the fleet's unique advantage is, today, roughly the meta-task of developing the fleet. That is a real but self-referential niche.

**Recommendation shape that follows:** do **not** invest in the full 12-item build-out speculatively. Gate it on demand — implement **rec 1 (managed daemons)** so the override is at least *available* without a manual boot ritual, run the **hybrid** (Workflow default, fleet on-demand) for a few weeks, and only build recs 2/4/6 (the deterministic-primitive parity work) **if** a recurring multi-session workload actually shows up. If after that window the fleet is still only ever used to develop itself, rip-it-out becomes the correct call. The recommendations below are therefore ordered and **sequenced by dependency**, not presented as an all-or-nothing program.

### Effort, sequencing, and critical path

T-shirt sizes are converted to hour ranges (focused implementation time, this codebase) and the dependency order is made explicit. **Rec 1 is a hard prerequisite, not merely "highest leverage first":** it gates rec 9 (frictionless inbox can't fail-safe without a live `:7977`) and the *entire* persistence/observability/capture pitch (recs 8, 10, 12 all assume daemons that stay up). Nothing downstream is worth building while the daemons remain hand-booted.

| Rec | Title | Hours | Depends on | On critical path? |
|---|---|---|---|---|
| 1 | Managed daemons (systemd units) | 3–6h | — | **YES — gates 8, 9, 10, 12 + all persistence** |
| 5 | Effort-aware fleet guard | 2–4h | — (independent) | Arbitrates the hybrid; do early |
| 3 | Structural forced report | 1–3h | — | No (local to `fleet-agent.sh`) |
| 7 | Reconcile CLI/path drift | 1–2h | — | No (hygiene) |
| 2 | Deterministic fan-out + barrier | 12–20h | 1 | Only if recurring multi-agent work appears |
| 4 | Schema-validated output | 4–8h | 2 (shares msg layer) | Only with 2 |
| 6 | Judge panel + budget governor | 12–20h | 1, 2 | Only with 2 |
| 8 | Framescope render→vision loop | 6–10h | 1 | Deferred (blocked on chromium/playwright) |
| 9 | Frictionless capture inbox | 2–4h | **1** | Yes — but worthless until 1 lands |
| 10 | Auto-capture from conversation | 3–6h | 1, 9 | After 9 |
| 11 | Relax doctrine + default capture verb | 2–4h | 9 | After 9 |
| 12 | Ambient surfacing + auto-clock | 4–8h | 1 | After 1 |

**Critical path to a usable hybrid:** rec 1 (3–6h) → rec 5 (2–4h) → rec 9 (2–4h) = **~7–14h** to go from "dead, must hand-boot" to "managed, arbitrated, with a real capture surface." Everything else (the deterministic-primitive parity, recs 2/4/6, ~28–48h) is **demand-gated** per the counterfactual above — build it only when a workload proves it is needed. Total if fully built out: **~52–95h**.

### Make the override real (close the orchestration + reliability gaps)

1. **Make the daemons managed services.** *What:* add systemd user units (declared in `~/code/nixos-config/modules/lodestar/default.bnix`) that run `lodestar up` (`:7977`), the `:7978` fleet coordinator, and the lodestar-web `:8088` bridge on login with auto-restart. *Why:* every other capability in this report is currently gated on "someone remembered to boot it" — `:7977` and `:8088` are both dead right now. This single fix turns persistence/observability/capture from aspirational to real, and it **gates recs 8, 9, 10, and 12** — build it first. *Effort:* 3–6h (one bnix module + 3 unit definitions + `firn-build`/commit). *Files:* `~/code/nixos-config/modules/lodestar/default.bnix`.

2. **Add a deterministic fan-out + barrier primitive.** *What:* `fleet-map <role-template> <N> <task>` that spawns/pings N workers, registers them under a `@batch:<id>` claim with expected-count, and a derived "complete when K DONE claims exist" query that auto-triggers synthesis. *Why:* this is the biggest single capability gap vs. Workflow — no map, no join, no reduce today. The claim graph + Datalog already support the derivation; only thin CLI verbs are missing. *Effort:* 12–20h. *Depends on:* rec 1. *Demand-gated* — build only if a recurring multi-agent workload appears. *Files:* `~/code/lodestar/fleet/cli/` (new `fleet-map`, barrier verb), `~/code/fleet-data/RUNBOOK.md`.

3. **Make the forced report structural, not prompt-level.** *What:* have the run wrapper detect a missing DONE/BLOCKED claim after the `claude -p` turn and auto-emit `BLOCKED("no report")` before going dormant. *Why:* delivery is currently guaranteed only by instruction text; `fleet-agent.sh:131` itself names dormant-without-finishing as a prior failure mode. *Effort:* 1–3h. *Files:* `~/code/fleet-data/fleet-agent.sh`.

4. **Add schema-validated structured output.** *What:* let a sender attach a JSON schema to a message; `fleet-listen`/the run wrapper validates the DONE payload before accepting it. *Why:* matches Workflow's `agent({schema})`+retry; today reports are freeform strings nothing rejects. *Effort:* 4–8h. *Depends on:* rec 2 (shares the msg layer). *Demand-gated.* *Files:* `~/code/lodestar/fleet/cli/msg-cli.clj`, `fleet-listen.clj`, `~/code/fleet-data/fleet-agent.sh`.

5. **Make the fleet guard effort-aware.** *What:* at `/fleet-guard on`, warn (or auto-bypass) when `effortLevel=="xhigh"`; add a SessionStart line echoing current `effortLevel` + sentinel state. *Why:* closes the latent contradiction (guard-on silently denies the Workflow fan-out that `xhigh` expects) and the invisibility gap (no agent can tell its own tier), and it becomes the **switch that arbitrates the hybrid** (Workflow vs. fleet mode). *Effort:* 2–4h. *Independent of rec 1 — do early.* *Files:* `~/code/nixos-config/dotfiles/claude/hooks/fleet-protocol-guard.sh`, a new/extended SessionStart hook, `settings.json`.

6. **Promote adversarial-verify + judge-panel to first-class patterns; add a budget governor.** *What:* a `verify-pair` (builder + falsifier must both sign off via claims before DONE is valid) and `judge-panel` (N inclusive judges, derived quorum); a `@budget:<team>` claim the engine checks at assign-time to hard-refuse spawns past depth/width/$ ceilings. *Why:* oakaudit-attest/falsify show the appetite but it's convention; "don't fork-bomb" is prompt-only. *Effort:* 12–20h. *Depends on:* recs 1, 2. *Demand-gated.* *Files:* `~/code/lodestar/fleet/cli/`, `~/code/fleet-data/spawn-agent.sh`, `fleet-agent.sh`.

7. **Reconcile CLI source + path drift.** *What:* symlink the two CLI copies to one source and fix `~/code/lodestar/CLAUDE.md:19` and the `bridge.bclj` `:file` annotations (still pointing at the deleted `~/code/lodestar-web`). *Why:* removes silent-divergence risk. *Effort:* 1–2h. *Files:* `~/code/lodestar/CLAUDE.md`, `~/code/lodestar/lodestar web/bridge/bridge.bclj`.

8. **Wire the lodestar-web render→vision loop.** *What:* headless chromium/playwright screenshot of `:8088` fed back to the commander's vision. *Why:* the actual multiplier the executive thread is chasing — deterministic visual ingest beats prose summaries. *Effort:* 6–10h. *Depends on:* rec 1; *blocked* on absent chromium/playwright — defer. *Files:* `~/code/lodestar/lodestar web/`, the blocked thread `2026-06-22-231850`.

### Make lodestar the default capture habit

9. **Ship a true frictionless inbox with NO triage at capture.** *What:* a `~/code/nixos-config/dotfiles/bin/` one-liner (e.g. `i "text"`) bound to a global hotkey, piping straight to `lodestar capture` with defaults (owner personal, draft lane, empty body) and zero questions; triage moves to a separate `needs-review` pass. *Why:* inverts the current triage-then-dump model into dump-then-triage — the one property a reflexive target needs. **Hard-depends on rec 1** (daemon up) to never fail — worthless until `:7977` is managed. *Effort:* 2–4h. *Files:* `~/code/nixos-config/dotfiles/bin/` (new script), kanata/desktop binding.

10. **Auto-capture from conversation.** *What:* a standing instruction/hook so when a TODO/bug/"I should…" surfaces mid-session, the AI captures it as a draft thread with a one-line confirm. *Why:* the 06-25 dogfooding captures prove this works when the AI is engaged — make it default, not an ask. *Effort:* 3–6h. *Depends on:* recs 1, 9. *Files:* a Claude hook + the operating manual's session-behavior section.

11. **Relax the doctrine for the inbox lane + make capture the default verb.** *What:* bless "capture everything into a draft lane" for the inbox; keep thread-purity for *committed* threads only; alias bare `lodestar "text"` → capture and add a shell alias `t`/`note`. *Why:* moves the "earn a shelf" bar from capture to promotion, and lowers keystroke cost below a markdown TODO. *Effort:* 2–4h. *Depends on:* rec 9. *Files:* `~/code/lodestar/docs/operating-manual.md`, `~/code/lodestar/bin/lodestar`.

12. **Turn surfacing ambient + auto-clock from cwd.** *What:* a session-start hook printing `next`/`ready` automatically; a direnv/shell hook that offers a clock against the matching thread on entering `~/code/<repo>`. *Why:* if the substrate greets you with what to do, you trust it with what to add; calibration data accrues without ritual. *Effort:* 4–8h. *Depends on:* rec 1. *Files:* a SessionStart hook, `~/code/nixos-config` direnv wiring.

## Open questions / unverified

- **Is `xhigh` actually the max effort tier?** Only the literal string `effortLevel="xhigh"` is file-backed; no repo file enumerates the valid values or calls `xhigh` the max. Per Anthropic docs the set is `low|medium|high|xhigh|max`, so `xhigh` is **not** the top (`max` is) — the "max/ultracode tier" label is inference.
- **`skipWorkflowUsageWarning` effect** is inferred from the key name; no file documents what warning it suppresses.
- **Daemon-side lease semantics** ("a second exclusive holder is refused at the daemon") are consistent with the design but uncited — `cnf_coord.clj`/`cnf_coord_daemon.clj` were not read; the CLI only checks `(:ok r)` on the response.
- **Did the fs-* team actually build the lodestar-web cockpit?** Those roles and per-agent logs exist, but no cited evidence ties the cockpit specifically to that team. Plausible, not demonstrated.
- **Live Workflow-spec primitives** (`agent/pipeline/parallel/phase/log/budget/nested workflow`, the 4096-items/call cap, `min(16,cores-2)`, `isolation`/`agentType`, the extended pattern library) are treated as ground truth but are **not publicly documented by Anthropic** — the closest public artifact is the hand-rolled "Build an orchestration mode" API example.
- **`MODE_REFRESH` every N turns** in the orchestration example was not present in the fetched content (`MODE_EXIT` is implied). Low-confidence detail.
