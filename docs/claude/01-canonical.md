# 01 · Canonical — how Claude Code works (the harness)

> HAND-CURATED, slow-rot. The stable model: how Claude Code assembles context,
> the levers you have to configure it, and **when to reach for each**. Update
> this when Anthropic changes the harness — NOT on every config edit (that's the
> generated local map, `02-local-map.md`).

## Context assembly — what reaches the model, in order

Once per session, then per turn. Every line is a lever you can pull.

```
ONCE PER SESSION
 ① base system prompt   baked in binary           CLI: append-only; full replace = SDK
 ② tool definitions     built-in + DEFERRED        permissions.deny removes; MCP/web deferred ≈ free
 ③ environment block    cwd / git / os / model     --exclude-dynamic-…-sections
 ④ CLAUDE.md hierarchy   global → ~/code → repo → subdir   edit files (broad→narrow)  ← primary bias lever
 ⑤ auto-memory          ~/.claude/projects/*/memory      autoMemoryEnabled (OFF here)
 ⑥ MCP instructions     prose + tool NAMES (schemas deferred)
 ⑦ skill descriptions   name + description only; BODY deferred until invoked
 ⑧ agent types          subagent roster
 ⑨ slash commands       commands/*.md
 ⑩ SessionStart hook    injected as a system message
EVERY TURN
 ⑪ user prompt
 ⑫ UserPromptSubmit hook    inject text / block the prompt
 ⑬ tool calls → results     PreToolUse: block / rewrite input · PostToolUse: rewrite output
 ⑭ compaction               old output → summary (PreCompact hook)
```

Key property: injected banners (caveman, beagle handshake) are **hook output**
(⑩/⑫), not model identity. Hooks alter the model's context without touching the
binary — that is the whole game.

## The levers — every knob

| lever | lives in | pull it for |
|---|---|---|
| **CLAUDE.md** | `dotfiles/claude/` + per-repo | persistent rules/context that should ALWAYS be in mind |
| **settings.json** | `dotfiles/claude/settings.json` | harness config: permissions, model/effort, statusLine, plugins, env |
| **hooks** | `settings.json` → `hooks/` | DETERMINISTIC behavior the model must not skip (enforce / inject / guard) |
| **skills** | `skills/` + plugins | ON-DEMAND procedural knowledge the model CHOOSES when relevant |
| **slash commands** | `commands/*.md` | user-typed shortcuts |
| **subagents** | agent dirs + plugins | parallel / isolated work in a separate context |
| **MCP servers** | `~/.claude.json` | external tools + data sources |
| **plugins** | `enabledPlugins` | packaged bundles of all the above |

## WHEN to use what — the decision that actually matters

The recurring confusion is **hooks vs skills vs CLAUDE.md**. The axis is *who
decides, and when*:

| if you want… | use | because |
|---|---|---|
| a rule always in the model's mind | **CLAUDE.md** | always loaded — but the model can still deprioritize/"forget" it |
| something to ALWAYS happen, zero model judgment | **hook** | the HARNESS runs it deterministically; the model cannot skip it |
| to BLOCK or rewrite a tool call / prompt | **hook** (Pre/PostToolUse, UserPromptSubmit) | only hooks sit in the loop and can intercept |
| procedural know-how applied WHEN relevant | **skill** | the model invokes it on judgment; the body loads only when needed (cheap) |
| a capability picked up situationally | **skill** | description is always visible, body is deferred |
| an external tool or data source | **MCP** | tools/data the harness doesn't ship |
| heavy / parallel / isolated work | **subagent** | separate context window, runs concurrently |
| to ship all of the above as one unit | **plugin** | bundles hooks + skills + commands + agents |

**The one-liner:**
- **hook** = harness enforces it (deterministic).
- **skill** = model chooses it (judgment).
- **CLAUDE.md** = always-on bias.

Decide by failure mode: *"the model might not do it and that's unacceptable"* →
**hook**. *"do it this way when it comes up"* → **skill**. *"keep this in mind"*
→ **CLAUDE.md**.

Hook events (CLI-confirmed): `SessionStart`, `SessionEnd`, `UserPromptSubmit`,
`PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`, `Notification`.

## Tool interception — swapping built-in behavior

Built-in tools (`Read`/`Bash`/`Edit`) are baked; you can't replace them directly.
Three swaps:

1. **Hook rewrite** — `PreToolUse` rewrites input args before exec; `PostToolUse`
   rewrites the output the model sees. Block-or-fake is possible.
2. **Shadow via MCP** — add `mcp__fs__read`, `deny` the built-in `Read`; the model
   routes through your implementation.
3. **SDK in-process tool** — define it as real code. True implementation swap (needs the SDK).

## CLI vs SDK vs API — escalate only at a ceiling

Same engine underneath. **Stay on the CLI for interactive work** — debloat, bias-
shift, and tool interception are all covered by what this repo already manages
(CLAUDE.md, hooks, permissions, plugin toggles). Reach for the **SDK** only at the
three things the CLI can't do: replace the base system prompt, real-code custom
tools, or programmatic per-call permission logic (`canUseTool`). **Raw API** only
if dropping the agent loop entirely.

Billing: the CLI here auths via OAuth subscription (`~/.claude/.credentials.json`);
the sanctioned production path for SDK/API is `ANTHROPIC_API_KEY` (pay-per-token).
Billing specifics move — confirm at docs.claude.com before building on subscription auth.
