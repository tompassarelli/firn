# Reference reads — vetted takeaways from ~/code/reference forks

Curated 2026-07-03 after a 4-repo scan (ponytail, superpowers, honey-for-devs,
Cortex). Licenses verified — all MIT; one carve-out noted below. Full scan
verdicts live in the session that produced this; this file keeps only the
pointers worth returning to.

## Skill authoring — read BEFORE writing a new skill

- `~/code/reference/superpowers/skills/writing-skills/SKILL.md` — the best
  available treatment of skill design: description-as-shortcut failure mode
  (agents read the description and skip the skill), "match the form to the
  failure" taxonomy (prohibition vs recipe vs structural vs conditional),
  wording micro-tests. Research-grounded (Cialdini 2021, Meincke 2025).
- `~/code/reference/superpowers/skills/writing-skills/testing-skills-with-subagents.md`
  — pressure-scenario protocol: RED-GREEN-REFACTOR applied to process docs,
  rationalization tables. How to test that a skill actually changes behavior.
- `~/code/reference/superpowers/skills/writing-skills/persuasion-principles.md`
  — persuasion research applied to making discipline-enforcing skills stick.

## Debugging techniques — reusable patterns

- `~/code/reference/superpowers/skills/systematic-debugging/find-polluter.sh`
  — bisects a test suite to find which test pollutes global state. Grab verbatim.
- `~/code/reference/superpowers/skills/systematic-debugging/condition-based-waiting.md`
  (+ `-example.ts`) — replace arbitrary timeouts with condition polling; the
  cure for flaky async tests.
- `~/code/reference/superpowers/skills/systematic-debugging/root-cause-tracing.md`
  — backward-trace through the call stack with a worked 5-level example.
- `~/code/reference/superpowers/skills/systematic-debugging/defense-in-depth.md`
  — 4-layer validation model (entry / business / environment guard / debug
  instrumentation).

## MCP + hook engineering — read when building tools that return big payloads

- `~/code/reference/Cortex/mcp_server/core/response_budget.py` — EMPIRICALLY
  MEASURED Claude Code MCP output ceiling: 25k tokens / 100k chars, UTF-16 vs
  code-point safety factor 0.75, priority-weighted water-fill truncation. Any
  north MCP tool returning variable-size payloads needs exactly this arithmetic.
- `~/code/reference/Cortex/mcp_server/core/gist_extraction.py` — deterministic
  head + signal-lines + tail gisting within a budget; the HIGH_VALUE_PATTERNS
  vocabulary (error/exception/decided/migrated/...) is a useful signal list.
- `~/code/reference/Cortex/mcp_server/core/context_assembly/condensers.py` —
  domain-aware condensing: code blocks verbatim, prose compressed,
  first + question + last sentences kept.
- `~/code/reference/ponytail/hooks/ponytail-runtime.js` `writeHookOutput()` —
  the multi-host hook-output template (Claude native vs Codex vs Copilot JSON
  shapes). Reference when making a hook portable.

## Benchmarking agent behavior

- `~/code/reference/ponytail/benchmarks/` — real headless Claude Code sessions,
  fresh repo per arm, `git diff` LOC scoring, adversarial safety tier. The
  methodology to copy if we ever benchmark compression/ESO variants properly
- `~/code/reference/honey-for-devs/bench/` — multi-model judge panel (4-model
  median), 3-tier task split (code / user-facing / agent-to-agent). Includes an
  honestly-documented negative result (prompt precompression: 2.5% real-world —
  they left it off). Model for honest measurement.

## Memory discipline

- `~/code/reference/honey-for-devs/skills/honey-memory/SKILL.md` — per-project
  memory file rules (same-change rule, stable-facts-only, terse). Tighter than
  most CLAUDE.md conventions; steal the constraints, not the file.

## License notes

All four repos MIT. Exception: `~/code/reference/honey-for-devs/hooks/eco.js` +
`hooks/eco-models.json` are MPL-2.0 (EcoLogits-derived, file-scoped copyleft) —
do not vendor those two files into MIT projects without keeping MPL terms.
`bench/headroom/fixtures/*.json` there are Apache-2.0 (bench-only).
