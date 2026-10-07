#!/usr/bin/env bash
# Tests for codex-behavior-guard.sh. Each failure it targets gets a case that
# must fire and a nearby ordinary case that must not: a guard that blocks
# normal work gets switched off.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/codex-behavior-guard.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/code/smashcraft/main" "$scratch/code/north/main" \
  "$scratch/code/clients/acme/main" "$scratch/code/wake/main"
printf 'profile: tooling\n' >"$scratch/code/wake/main/AGENTS.md"
export PATH="/etc/codex/hooks/runtime:$PATH"
export CODEX_BEHAVIOR_CODE_ROOT="$scratch/code" CODEX_BEHAVIOR_STATE="$scratch/state"
pass=0 fail=0

run() { AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" 2>/dev/null; }

expect() { # expect <name> <fires|quiet> <grep-pattern-or-empty> <event-json>
  local name="$1" want="$2" pattern="$3" out
  out="$(printf '%s' "$4" | run)"
  if [ "$want" = quiet ] && [ -z "$out" ]; then pass=$((pass + 1)); return; fi
  if [ "$want" = fires ] && [ -n "$out" ] && grep -q -- "$pattern" <<<"$out"; then
    pass=$((pass + 1)); return
  fi
  fail=$((fail + 1)); printf 'FAIL %s: got %s\n' "$name" "${out:-<nothing>}"
}

prompt() { printf '{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":%s}' "$1"; }
plan() { # plan <cwd> <explanation> <steps-json>
  printf '{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"%s","tool_name":"update_plan","tool_input":{"explanation":%s,"plan":%s}}' "$1" "$2" "$3"
}
stopping() { printf '{"hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":%s}' "$1" "$2"; }

good_list='"Fix the jump arc.\nprofile: prototype\ndone-when: jump test passes; one native match plays\nextra checks: none\nworkers: none"'
steps='[{"step":"Fix jump arc","status":"pending"},{"step":"Play one native match","status":"pending"}]'
game="$scratch/code/smashcraft/main"

# Corrections add context; ordinary prompts don't.
expect correction fires 'Tom is correcting you' "$(prompt '"why are you still adding reviewers, I told you to ship"')"
expect plain-request quiet '' "$(prompt '"Add a controller rumble setting to the options menu"')"

# First plans need the cited checklist, with the right profile.
expect missing-checklist fires 'missing: profile' "$(plan "$game" '"Fix the jump arc."' "$steps")"
expect good-plan quiet '' "$(plan "$game" "$good_list" "$steps")"
expect wrong-profile fires "gives 'tooling'" "$(plan "$scratch/code/north/main" "$good_list" "$steps")"
expect repo-override fires "gives 'tooling'" "$(plan "$scratch/code/wake/main" "$good_list" "$steps")"
expect client-profile fires "gives 'client'" "$(plan "$scratch/code/clients/acme/main" "$good_list" "$steps")"
expect unnamed-extra-check fires 'new failure' "$(plan "$game" '"x\nprofile: prototype\ndone-when: a\nextra checks: run the soak\nworkers: none"' "$steps")"
expect named-extra-check quiet '' "$(plan "$game" '"x\nprofile: prototype\ndone-when: a\nextra checks: frame test catches dropped inputs\nworkers: none"' "$steps")"

# Process steps are rejected unless Tom asked; ordinary verification is not.
expect reviewer-step fires 'extra review' "$(plan "$game" "$good_list" '[{"step":"Spawn an independent reviewer to audit the patch","status":"pending"}]')"
expect confidence-rerun fires 'passing check' "$(plan "$game" "$good_list" '[{"step":"Re-run the passing suite for confidence","status":"pending"}]')"
expect failing-test-rerun quiet '' "$(plan "$game" "$good_list" '[{"step":"Re-run the failing test to confirm the fix","status":"pending"}]')"
expect code-guard quiet '' "$(plan "$game" "$good_list" '[{"step":"Add a guard for empty input","status":"pending"}]')"
expect compat-shim fires 'compatibility' "$(plan "$game" "$good_list" '[{"step":"Keep a compatibility shim for old saves","status":"pending"}]')"
expect unasked-skill-edit fires 'policy or skill edit' "$(plan "$game" "$good_list" '[{"step":"Update the warcraft-modding skill","status":"pending"}]')"
prompt '"update the warcraft-modding skill with the new reload trick"' | run >/dev/null
expect asked-skill-edit quiet '' "$(plan "$game" "$good_list" '[{"step":"Update the warcraft-modding skill","status":"pending"}]')"
expect progress-update-plan quiet '' "$(plan "$game" "$good_list" '[{"step":"Fix arc","status":"completed"},{"step":"Play match","status":"in_progress"}]')"
prompt '"no soak this time, just ship the map"' | run >/dev/null
expect negated-mention fires 'canary or soak' "$(plan "$game" "$good_list" '[{"step":"Run a 20-minute soak","status":"pending"}]')"

# Endings: asking, narrating, disclaimers and uncounted "nearly done".
expect asks-permission fires 'asking permission' "$(stopping false '"Built the map. Should I also push it to main?"')"
expect needs-you quiet '' "$(stopping false '"Blocked: needs a paid account.\nNeeds you: approve the $5 plan? I recommend yes."')"
expect narrates fires 'progress update' "$(stopping false '"Tests pass.\nNext, I will update the docs."')"
expect disclaimer fires 'doesn'"'"'t prove' "$(stopping false '"Done: 20/20 taps land. This does not prove frame-exact timing."')"
expect nearly-uncounted fires 'count' "$(stopping false '"We are nearly done."')"
expect nearly-counted quiet '' "$(stopping false '"Nearly done: 2 of 5 boxes left."')"
expect clean-report quiet '' "$(stopping false '"Done: controller works; 904 presses, 0 missed.\nNeeds you: nothing"')"
expect already-continued quiet '' "$(stopping true '"Should I push it?"')"

# Off switch and malformed input allow.
out="$(prompt '"stop asking, wtf"' | AGENT_NO_AUTHORING_HOOKS=1 "$HOOK" 2>/dev/null)"
if [ -z "$out" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL killswitch"; fi
expect malformed quiet '' "$(printf 'not json')"

printf 'codex-behavior-guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
