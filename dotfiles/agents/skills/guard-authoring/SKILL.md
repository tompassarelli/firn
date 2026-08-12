---
name: guard-authoring
category: agents
description: >-
  Use whenever a request means a new or changed enforcement hook on this
  machine — "add a hook that stops agents from doing X", "block <command>",
  "make agents refuse Y", "warn when someone edits Z", "wire up a guard", or
  debugging a guard that fires in Claude Code but not Codex (or not for
  north-dispatched workers). A hook here is correct only when it lands in
  several places at once: the script, the switchboard manifest, Codex's static
  managed manifest, and North Bridge's worker guard chain — and only when
  something CLAIMS it, because default state is off and an unclaimed hook
  reaches nobody. Covers the deny protocol, both tool entrances
  (`tool_input.file_path` and `tool_input.command`), fail-open, the kill-switch
  preamble, and the two-direction test matrix.
---

# Authoring a guard on this machine

A guard is a `PreToolUse` hook: the only event that can refuse a tool call
*before* the write or the command lands. Writing the script is the easy half.
The half that gets rediscovered every time — and half-done every time — is that
one guard has to be true in four places at once, and is off by default in all
of them.

Read this before writing the script, because two of the four places constrain
what the script may look like.

Paths below are written `repo:path`, which resolves to
`~/code/<repo>/main/<path>` — `~/code/<repo>` is a container, not a checkout,
and you edit in a `wt-<slug>` sibling, never in `main/`.

## The four places

| What | Where | Lands by |
|---|---|---|
| the script | `north:profiles/tom/hooks/<name>.sh` | live immediately |
| Claude Code wiring | `nixos-config:dotfiles/agents/hooks.d/<name>.json` + `HOOKS` in `nixos-config:dotfiles/bin/agents` | `agents apply` |
| Codex wiring | `nixos-config:modules/codex/requirements.toml`, `modules/codex/default.bnix`, `dotfiles/codex/hooks.json`, `north:sdk/src/providers/codex-managed-hooks.ts` | rebuild + enforcement promote |
| North Bridge wiring | `EDIT_GUARDS` / `BASH_GUARDS` / `WORKER_BASH_GUARDS` in `north:sdk/src/harness.ts` | live from the checkout |

`~/.agents/hooks` is a home-manager out-of-store symlink to
`north:profiles/tom/hooks` (via the `agent-profile` → `profiles/tom` link), so
editing the script there is immediately live for everything that reads the
directory — no rebuild. `~/.agents/hooks` is a PROJECTION: never author there,
author in the checkout. Same for `~/.claude`, `~/.codex`, `/etc/codex`.

A Firn-specific guard is the one exception to the script's home: it lives at
`nixos-config:modules/north-profile/firn/hooks/firn-guard.sh` and is symlinked
into the hooks directory. Follow the existing file rather than moving it.

## The script

### Preamble, in this order

Every guard here starts the same way, and the order is load-bearing:

```bash
#!/usr/bin/env bash
set -uo pipefail

# 1. Drain stdin COMPLETELY before any decision. An undrained payload can block
#    the writer on the other end. Bound it (~1 MiB) and fail open past that.
payload=""
while :; do
  chunk=""; IFS= read -r -N 65536 chunk; status=$?
  [ -n "$chunk" ] && payload+="$chunk"
  [ "$status" -eq 0 ] || break
done

# 2. Kill-switch — the SHARED implementation, sourced not shelled out to.
#    This one call gives you `north config guards off`, the
#    AGENT_NO_AUTHORING_HOOKS env override, the per-hook/per-category dial, and
#    the switchboard gate that Codex has no other way to get (below).
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

# 3. Cheap bash pre-filter. This runs on EVERY matching tool call, so a payload
#    that cannot possibly be interesting must not pay a python3 startup.
case "$payload" in *git*) ;; *) exit 0 ;; esac

# 4. Decide. Silence is "no opinion" and is by far the common case.
```

Step 2 is why the switchboard can turn a Codex guard off at all: Claude Code
composes only active hooks into its settings, but Codex's managed manifest is
static and machine-wide, so the gate has to live inside the script.
`authoring_guards_off` reads it through `lib/harness-dial.sh` →
`lib/switchboard-activity.sh` → `~/.config/agents/activity.conf`.

### Deny protocol

Two shapes are accepted, and Claude Code, Codex, and North's `evaluateGuards`
all understand both:

```
stdout JSON, exit 0:
  {"hookSpecificOutput":{"hookEventName":"PreToolUse",
                         "permissionDecision":"deny",
                         "permissionDecisionReason":"<what to do instead>"}}

exit 2, one line of reason on stderr
```

Prefer the JSON form — the reason field is what the agent actually reads, and
stdout-JSON deny wins over exit-2 when both appear. `"ask"` is available where
a human decision is the right outcome. Anything else — empty stdout, exit 0 —
means allow, and that must be the cheap path.

### Fail open, always

Missing `python3`, unreadable payload, malformed JSON, an unresolvable path,
any unexpected error: print nothing, exit 0, let the call through. A guard that
blocks work when the guard itself is broken is worse than the leak it prevents,
and it will get switched off wholesale rather than fixed.

## The four rules that get rediscovered

**Enforce on every entrance.** A guard matched only on `Edit|Write|MultiEdit`
is not enforcement — the identical action goes through `Bash` (`sed -i`,
`python3 -c`, a heredoc, `git checkout`). The payload differs by entrance:
`tool_input.file_path` on Edit/Write/MultiEdit, `tool_input.command` on Bash,
and on Codex an `apply_patch` envelope whose paths may be relative and need
resolving. Parse whichever your matchers can receive. `~/code/CLAUDE.md` states
this flatly for the worktree guard: *enforcement on one entrance is not
enforcement.*

**Never trap a lane with no compliant move.** The denial message must name the
legal path, because a denial is information about the path, not about the goal.
An agent with no way forward will route around the guard, stall, or spend a
user's money rediscovering the exit. The worktree guard deliberately permits
reads, `git worktree add`, `pull --ff-only`, and `wt-rescue` for exactly this
reason. Write the reason as an instruction ("enumerate the paths you intend to
commit, e.g. `git add path/to/file`"), not as a verdict.

**Refuse the expensive or dangerous SHAPE, not the whole surface.** An
over-broad guard is worse than no guard: it gets disabled, and everything it
covered goes with it. The blind-stage guard denies `git add -A` at *command
position* and deliberately allows a commit message that quotes the phrase —
because denying that would be maddening and would end the guard's life. Decide
what precise shape is expensive, and let everything adjacent through.

**Both providers and the bridge, or it did not land.** These are three
independent wirings and a guard present in one is genuinely absent from the
others. The bridge case is the quiet one: `north:sdk/src/harness.ts` builds
worker options with `settingSources: []`, so a north-dispatched worker never
reads `~/.claude/settings.json` — it runs exactly the scripts named in
`EDIT_GUARDS` / `BASH_GUARDS` / `WORKER_BASH_GUARDS` and nothing else. As of
this writing those chains carry only `firn-guard`, `tripwire-guard`, and
`agent-spawn-guard`; the worktree and blind-stage guards are wired for
interactive sessions and *not* for workers. Do not read that as the pattern —
it is the gap this skill exists to stop repeating. Check the arrays, don't
assume them.

## Wiring, place by place

### Claude Code

`nixos-config:dotfiles/agents/hooks.d/<name>.json`:

```json
{
 "entries": [
  {"event": "PreToolUse", "matcher": "Edit|Write|MultiEdit",
   "hook": {"type": "command",
            "command": "/home/tom/.agents/hooks/<name>.sh", "timeout": 10}},
  {"event": "PreToolUse", "matcher": "Bash",
   "hook": {"type": "command",
            "command": "/home/tom/.agents/hooks/<name>.sh", "timeout": 10}}
 ],
 "tags": ["guards"],
 "follows": "<unit>",
 "requires": []
}
```

Then add the bare name to the `HOOKS` array in `nixos-config:dotfiles/bin/agents`
(alphabetical), and run `agents apply` — that is the only writer of the `hooks`
key in `~/.claude/settings.json`.

**Give it a claimant, or it reaches nobody.** The switchboard is two axes:
PERMISSION (`enabled`/`disabled`, the user's, stored) and ACTIVITY (derived:
permission AND some claimant active). A hook's claimants are the unit named in
`follows`, plus every skill whose SKILL.md frontmatter lists it under `hooks:`.
An unclaimed hook seeds `disabled` and stays dark; a claimed one seeds `enabled`
but is still inactive until its claimant is on. Prefer the skill-side claim —
the skill is what knows which enforcement its rules need, and it puts the
statement in one file instead of scattering it:

```yaml
hooks:
  - <name>
```

A guard whose rules are already written down belongs to that skill's `hooks:`
list (`repo-safety` claims the worktree, blind-stage, and tripwire guards).
A guard that is pure infrastructure gets no claimant and answers only to a
direct `agents on <name>`.

`requires: []` names other hooks this one cannot work without; the chain is
composed whole or not at all.

**Do not flip it on for the user.** Default off is the configured answer, not a
fault to route around. Wire it, verify it, and say it is ready — activation is
the user's call.

### Codex

Codex trusts a hook by the provenance of `/etc/codex/requirements.toml`
(`allow_managed_hooks_only = true`, `managed_hook_failure_mode = "block"`),
never by where the file sits. Four edits:

1. `nixos-config:modules/codex/requirements.toml` — the matcher block. Matchers
   here are ANCHORED REGEXES, not Claude's alternation:
   `^(Edit|Write|MultiEdit|apply_patch)$`, `^Bash$`. The command is always
   `/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV /etc/codex/hooks/runtime/bash /etc/codex/hooks/<name>.sh`
   — the pinned runtime, so a hook cannot inherit a surprising interpreter.
2. `nixos-config:modules/codex/default.bnix` — a `promoted "<name>.sh"
   "north/profiles/tom/hooks/<name>.sh"` tmpfiles rule, which is how the script
   appears at `/etc/codex/hooks/<name>.sh` out of the promoted enforcement
   snapshot rather than out of the store.
3. `nixos-config:dotfiles/codex/hooks.json` — the user-level `~/.codex/hooks.json`,
   kept in step so the two do not disagree.
4. `north:sdk/src/providers/codex-managed-hooks.ts` — add the entry to
   `PROMOTED_HOOK_SOURCES` and to `expectedManagedCodexHooks()`. North verifies
   the live install against this; drift makes the spawn doctor fail, naming
   both identities.

The manifest rides a **rebuild** (hand the user the command — agents do not
fire rebuilds); the script itself rides an **enforcement promote**. They land
separately, so expect a window where one is ahead of the other, and make sure
the script's absence fails open rather than blocking.

### North Bridge

Add the script's basename to the right chain in `north:sdk/src/harness.ts`:
`EDIT_GUARDS` for `Edit|Write|MultiEdit`, `BASH_GUARDS` for Bash in an
orchestration-allowed lane, `WORKER_BASH_GUARDS` for a plain worker.
`resolveManagedGuardChain` resolves each name against `~/.agents/hooks` and
silently drops what is not there, so a typo is a guard that never runs and
never complains. First deny in a chain wins.

A Bash guard belongs in **both** Bash chains by default. They are not
interactive-vs-worker: `BASH_GUARDS` is a lane allowed to orchestrate and
`WORKER_BASH_GUARDS` is one that is not, and a plain worker is the lane least
able to notice it is doing the expensive thing. Naming only one is a choice you
should be able to justify out loud, not the safe default.

### The inventory row

`north:profiles/tom/hooks/registry.tsv` is the one table answering "what hooks
exist" for the bash dial, the Clojure report, and the TS SDK. Add a row:

```
<name>	authoring	deny	yes	yes	<name>.sh	PreToolUse:Edit|Write|MultiEdit,PreToolUse:Bash
```

`kind` is `deny` (can refuse) / `advisory` (shapes output) / `identity`.
`in_all` is whether the `hooks` sweep reaches it. `ttl_req` forces `--until` on
an off for deny-capable hooks, so a permanent silent disable cannot be an
accident. A hook with no row has no category, which means `north config guards`
cannot address it and only the `all` sweep touches it.

## Tests — both directions

Put the matrix beside the script: `north:profiles/tom/hooks/<name>.test.sh`.
Feed the hook a real payload on stdin and read back the decision; the existing
`git-blind-stage-guard.test.sh` is the shape to copy — sandbox `HOME`, a
`run deny|allow <desc> <command>` helper, one line per case.

A guard tested only on the bad shape will silently over-block, and over-blocking
is what gets guards switched off. Every matrix needs both halves:

```
== the expensive shape is refused ==
run deny  'bare form'               '<the thing>'
run deny  'behind sudo'             'sudo <the thing>'
run deny  'after a separator'       'printf ready && <the thing>'
run deny  'on a second line'        $'printf ready\n<the thing>'
run deny  'through the OTHER entrance'   # file_path payload, not command

== the legitimate neighbours still pass ==
run allow 'the sanctioned alternative'   '<what the deny message tells them>'
run allow 'the phrase inside a commit message'
run allow 'the phrase inside a heredoc body'
run allow 'a scoped//narrow form that is cheap'
```

The false-positive half is not optional: the sanctioned alternative named in
your own denial message must have a passing test, or the guard can trap a lane
and nobody will notice until an agent is stuck.

Two suites above the script:

- `nixos-config:dotfiles/bin/agents.test.sh` — switchboard semantics. **It has
  the hook count hardcoded twice** (`chk "on --all: every fragment composed"
  "10"` and `chk "off --all: hooks disabled" "10"`); adding a fragment makes it
  11 and both must be bumped. It is slow — run it in the background with output
  to a log and a bounded wait, never a silent idle.
- `nixos-config:scripts/agent-config-check.sh` — the provider-neutral anti-rot
  check across the harness and its adapters.

## Verify it landed

Run these; each answers exactly one of the four places.

```bash
agents status | grep <name>          # permission, activity, and who claims it
python3 -c "import json;print(json.load(open('$HOME/.claude/settings.json'))['hooks'])"
grep -n <name> /etc/codex/requirements.toml; ls -l /etc/codex/hooks/<name>.sh
grep -n <name> ~/code/north/main/sdk/src/harness.ts
bash ~/.agents/hooks/<name>.test.sh
echo '{"tool_name":"Bash","tool_input":{"command":"<the bad shape>"}}' \
  | ~/.agents/hooks/<name>.sh    # expect the deny JSON
```

`agents status` showing `off (skill: <x> off)` is a correctly wired hook whose
claimant is not on — that is a report, not a failure. `(no fragment)` means the
manifest is missing. Nothing at all means it is absent from the `HOOKS` array.

## Worked example — `launch-critical-worktree-guard`

The one guard that is wired everywhere, and the reference to read when in doubt:

- script `north:profiles/tom/hooks/launch-critical-worktree-guard.sh`, decision
  split out to `lib/launch_critical_decide.py` so it can be tested directly
  rather than through a heredoc
- registry row `launch-critical-worktree-guard  authoring  deny  yes  yes …`
- Claude Code: `hooks.d/worktree-guard.json`, two entries (Edit/Write/MultiEdit
  **and** Bash), `"follows": "repo-safety"` — plus `repo-safety`'s SKILL.md
  claiming `worktree-guard` under `hooks:`
- Codex: `requirements.toml` on `^(Edit|Write|MultiEdit|apply_patch)$` and
  `^Bash$`, `default.bnix` promote rule, `codex-managed-hooks.ts` entry
- carve-outs so no lane is trapped: worktrees by name, `wt-rescue`,
  gitignored paths, and reads
- tests `launch-critical-worktree-guard.test.sh` + `.test.py`

Note what it is *not*: it is not in the harness worker chains. That is the
known gap, not the pattern.
