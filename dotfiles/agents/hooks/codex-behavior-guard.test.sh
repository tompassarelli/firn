#!/usr/bin/env bash
# Tests for codex-behavior-guard.sh. Each failure it targets gets a case that
# must fire and a nearby ordinary case that must not: a guard that blocks
# normal work gets switched off.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/codex-behavior-guard.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
code="$scratch/code"
game="$code/smashcraft/main"
mkdir -p "$game" "$code/north/main" "$code/clients/acme/main" "$code/wake/main"
printf 'profile: tooling\n' >"$code/wake/main/AGENTS.md"
git -C "$game" init -q && printf 'a\n' >"$game/arc.ts" && git -C "$game" add arc.ts \
  && git -C "$game" -c user.name=t -c user.email=t@t commit -qm init
export PATH="/etc/codex/hooks/runtime:$PATH"
export CODEX_BEHAVIOR_CODE_ROOT="$code" CODEX_BEHAVIOR_STATE="$scratch/state"
pass=0 fail=0

run() { AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" 2>/dev/null; }

expect() { # expect <name> <fires|quiet|lacks> <pattern-or-empty> <event-json>
  local name="$1" want="$2" pattern="$3" out
  out="$(printf '%s' "$4" | run)"
  case "$want" in
    quiet) [ -z "$out" ] && { pass=$((pass + 1)); return; } ;;
    fires) [ -n "$out" ] && grep -q -- "$pattern" <<<"$out" && { pass=$((pass + 1)); return; } ;;
    lacks) [ -n "$out" ] && ! grep -q -- "$pattern" <<<"$out" && { pass=$((pass + 1)); return; } ;;
  esac
  fail=$((fail + 1)); printf 'FAIL %s: got %s\n' "$name" "${out:-<nothing>}"
}

prompt() { printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","prompt":%s}' "$1" "$2"; }
plan() { # plan <session> <cwd> <explanation> <steps-json>
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"update_plan","tool_input":{"explanation":%s,"plan":%s}}' "$1" "$2" "$3" "$4"
}
pre() { # pre <session> <cwd> <command-json>
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' "$1" "$2" "$3"
}
post() { # post <session> <cwd> <command-json> <exit-code>
  printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s},"tool_response":"Exit code: %s\\nOutput:\\nok"}' "$1" "$2" "$3" "$4"
}
stopping() { printf '{"hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":%s}' "$1" "$2"; }

# Prompts: every prompt shows the score; corrections and close requests add their rule.
expect correction fires 'Tom is correcting you' "$(prompt c1 '"why are you still adding reviewers, I told you to ship"')"
expect plain-request fires 'Scoreboard' "$(prompt c1 '"Add a controller rumble setting to the options menu"')"
expect plain-no-correction lacks 'correcting' "$(prompt c1 '"Add a controller rumble setting to the options menu"')"
expect close-request fires 'Tom wants this closed' "$(prompt c1 '"https://github.com/tompassarelli/wisp/issues/19 -> how the fuck is this not done yet"')"
expect close-menu-feature lacks 'wants this closed' "$(prompt c1 '"Close the pause menu when Escape is pressed"')"

# First plans: goal quoted from the request, profile, Done-when, extra checks, workers, ETA.
prompt p1 '"Fix the jump arc so the arc matches Melee"' | run >/dev/null
list() { printf '"x\\ngoal: \\"%s\\"\\nprofile: %s\\ndone-when: jump test passes\\nextra checks: %s\\nworkers: none\\neta: %s"' "$1" "$2" "$3" "$4"; }
good="$(list 'fix the jump arc' prototype none '20 min')"
steps='[{"step":"Fix jump arc","status":"pending"},{"step":"Play one native match","status":"pending"}]'
expect missing-checklist fires 'missing: goal' "$(plan p1 "$game" '"Fix the jump arc."' "$steps")"
expect good-plan quiet '' "$(plan p1 "$game" "$good" "$steps")"
expect invented-goal fires 'word for word' "$(plan p1 "$game" "$(list 'rewrite the physics engine' prototype none '20 min')" "$steps")"
expect wrong-profile fires "is 'tooling'" "$(plan p1 "$code/north/main" "$good" "$steps")"
expect repo-override fires "is 'tooling'" "$(plan p1 "$code/wake/main" "$good" "$steps")"
expect client-profile fires "is 'client'" "$(plan p1 "$code/clients/acme/main" "$good" "$steps")"
expect unnamed-extra-check fires 'new failure' "$(plan p1 "$game" "$(list 'fix the jump arc' prototype 'run the soak' '20 min')" "$steps")"
expect named-extra-check quiet '' "$(plan p1 "$game" "$(list 'fix the jump arc' prototype 'frame test catches dropped inputs' '20 min')" "$steps")"
expect bad-eta fires 'eta' "$(plan p1 "$game" "$(list 'fix the jump arc' prototype none soon)" "$steps")"
expect worker-without-prompts quiet '' "$(plan w1 "$game" "$(list 'whatever the brief said' prototype none '15 min')" "$steps")"

# Process steps are refused unless the request asked; ordinary verification is not.
expect reviewer-step fires 'extra review' "$(plan p1 "$game" "$good" '[{"step":"Spawn an independent reviewer to audit the patch","status":"pending"}]')"
expect confidence-rerun fires 'passing check' "$(plan p1 "$game" "$good" '[{"step":"Re-run the passing suite for confidence","status":"pending"}]')"
expect failing-test-rerun quiet '' "$(plan p1 "$game" "$good" '[{"step":"Re-run the failing test to confirm the fix","status":"pending"}]')"
expect code-guard quiet '' "$(plan p1 "$game" "$good" '[{"step":"Add a guard for empty input","status":"pending"}]')"
expect compat-shim fires 'compatibility' "$(plan p1 "$game" "$good" '[{"step":"Keep a compatibility shim for old saves","status":"pending"}]')"
expect unasked-skill-edit fires 'policy or skill edit' "$(plan p1 "$game" "$good" '[{"step":"Update the warcraft-modding skill","status":"pending"}]')"
prompt p1 '"update the warcraft-modding skill with the new reload trick"' | run >/dev/null
expect asked-skill-edit quiet '' "$(plan p1 "$game" "$good" '[{"step":"Update the warcraft-modding skill","status":"pending"}]')"
prompt p1 '"no soak this time, just ship the map"' | run >/dev/null
expect negated-mention fires 'canary or soak' "$(plan p1 "$game" "$good" '[{"step":"Run a 20-minute soak","status":"pending"}]')"
expect progress-update-plan quiet '' "$(plan p1 "$game" "$good" '[{"step":"Fix arc","status":"completed"},{"step":"Play match","status":"in_progress"}]')"

# Checks: a rerun on unchanged code is refused; changed code, a failure or a named reason allows.
expect first-run quiet '' "$(pre b1 "$game" '"bun test"')"
post b1 "$game" '"bun test"' 0 | run >/dev/null
expect unchanged-rerun fires 'passed at' "$(pre b1 "$game" '"bun test"')"
expect named-rerun quiet '' "$(pre b1 "$game" '"RERUN_BECAUSE=\"flaky timer on pair 15\" bun test"')"
expect other-command quiet '' "$(pre b1 "$game" '"git status"')"
printf 'b\n' >>"$game/arc.ts"
expect changed-code quiet '' "$(pre b1 "$game" '"bun test"')"
post b1 "$game" '"bun test"' 1 | run >/dev/null
expect after-failure quiet '' "$(pre b1 "$game" '"bun test"')"
post b1 "$game" '"cd ts && bun run check"' 0 | run >/dev/null
expect chained-check-rerun fires 'passed at' "$(pre b1 "$game" '"cd ts && bun run check"')"

# Issues: the shape must be closable, and a session can't open faster than it closes.
body='## Done when\n- [ ] jump test passes\n## Not required\n- netcode'
expect good-issue quiet '' "$(pre i1 "$game" "\"gh issue create --title Jump --body \\\"$body\\\"\"")"
expect no-not-required fires 'Not required' "$(pre i1 "$game" '"gh issue create --title Jump --body \"## Done when\n- [ ] jump test passes\""')"
expect too-many-boxes fires 'at most 5' "$(pre i1 "$game" '"gh issue create --title J --body \"## Done when\n- [ ] a\n- [ ] b\n- [ ] c\n- [ ] d\n- [ ] e\n- [ ] f\n## Not required\n- x\""')"
expect guarantee-box fires 'measured check' "$(pre i1 "$game" '"gh issue create --title J --body \"## Done when\n- [ ] never loses an input\n## Not required\n- x\""')"
post i1 "$game" '"gh issue create --title Jump"' 0 | run >/dev/null
expect opens-past-closes fires 'Close one before' "$(pre i1 "$game" "\"gh issue create --title Next --body \\\"$body\\\"\"")"
prompt i1 '"please file issues for each bug you found"' | run >/dev/null
expect asked-for-issues quiet '' "$(pre i1 "$game" "\"gh issue create --title Next --body \\\"$body\\\"\"")"
expect label-edit quiet '' "$(pre i1 "$game" '"gh issue edit 5 --add-label later"')"
expect existing-issue-edit quiet '' "$(pre i1 "$game" '"gh issue edit 5 --body \"## Done when\n- [ ] always on frame\""')"
post i1 "$game" '"gh issue close 12"' 0 | run >/dev/null
expect score-counts-close fires '1 issues closed' "$(prompt i1 '"status?"')"

# ETA: past twice the planned minutes, the next shell result says so once.
prompt e1 '"Fix the jump arc so the arc matches Melee"' | run >/dev/null
plan e1 "$game" "$(list 'fix the jump arc' prototype none '1 min')" "$steps" | run >/dev/null
expect within-eta quiet '' "$(post e1 "$game" '"ls"' 0)"
python3 - "$scratch/state/e1.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path))
state["eta"]["set_at"] -= 600
json.dump(state, open(path, "w"))
PY
expect past-eta fires 'twice over' "$(post e1 "$game" '"ls"' 0)"
expect warned-once quiet '' "$(post e1 "$game" '"ls"' 0)"

# Endings: asking, narrating, handing off, disclaimers and uncounted "nearly done".
expect asks-permission fires 'asking permission' "$(stopping false '"Built the map. Should I also push it to main?"')"
expect needs-you quiet '' "$(stopping false '"Blocked: needs a paid account.\nNeeds you: approve the $5 plan? I recommend yes."')"
expect narrates fires 'not an ending' "$(stopping false '"Tests pass.\nNext, I will update the docs."')"
expect delegates-last-box fires 'not an ending' "$(stopping false '"#19 is 2/3 done. I failed to assign that final measurement a dedicated owner and a quiet run. I'"'"'m doing that now; if the comparison fails, that worker owns correcting the model."')"
expect assigns-worker fires 'not an ending' "$(stopping false '"Two boxes pass. Assigning the native rerun to a worker on pair 15."')"
expect disclaimer fires 'doesn'"'"'t prove' "$(stopping false '"Done: 20/20 taps land. This does not prove frame-exact timing."')"
expect nearly-uncounted fires 'count' "$(stopping false '"We are nearly done."')"
expect nearly-counted quiet '' "$(stopping false '"Nearly done: 2 of 5 boxes left."')"
expect closed-with-number quiet '' "$(stopping false '"Closed #19: four-fighter p95 predicted within 12% of native.\nNeeds you: nothing"')"
expect already-continued quiet '' "$(stopping true '"Should I push it?"')"

# A tool reported missing without an error from calling it.
expect invented-missing-tool fires 'never got an error' "$(stopping false '"Yes, there is an orchestration blocker. This turn lacks send_message / followup_task, so five workers are still waiting.\nNeeds you: restore those collaboration tools to this root session."')"
expect real-missing-tool quiet '' "$(stopping false '"Blocked: shellcheck is unavailable; calling it failed with: command not found.\nNeeds you: nothing, installing it now."')"

# Escalating without an attempt: try first, come back with the error.
expect untried-escalation fires 'without having tried' "$(stopping false '"Blocked: I am not sure the shared server supports resume.\nNeeds you: confirm it is safe to restart."')"
expect tried-escalation quiet '' "$(stopping false '"Blocked: bun test failed with exit code 1 on arc.test.ts.\nNeeds you: decide whether the arc follows Melee or Ultimate."')"
expect product-choice quiet '' "$(stopping false '"Blocked: two designs fit.\nNeeds you: choose between ledge-cancel on or off. I recommend on."')"

# A long run of read-only commands with no change gets told to try something.
patch_post() { printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch"},"tool_response":"ok"}' "$1" "$2"; }
for _ in $(seq 1 19); do post r1 "$game" '"rg jumpArc ts/src"' 0 | run >/dev/null; done
expect twentieth-read fires 'Stop reading' "$(post r1 "$game" '"git log --oneline -5"' 0)"
expect after-limit quiet '' "$(post r1 "$game" '"cat ts/src/arc.ts"' 0)"
patch_post r1 "$game" | run >/dev/null
for _ in $(seq 1 18); do post r1 "$game" '"sed -n 1,40p ts/src/arc.ts"' 0 | run >/dev/null; done
expect reset-by-patch quiet '' "$(post r1 "$game" '"rg arc"' 0)"
post r2 "$game" '"bun run build"' 0 | run >/dev/null
for _ in $(seq 1 19); do post r2 "$game" '"ls"' 0 | run >/dev/null; done
expect build-counts-as-action fires 'Stop reading' "$(post r2 "$game" '"ls"' 0)"
expect sed-in-place-is-action quiet '' "$(post r3 "$game" '"sed -i s/a/b/ arc.ts"' 0)"

# A stop request means stop now, and running on gets a reminder every five commands.
expect stop-request fires 'Tom asked you to stop' "$(prompt s1 '"Heads-up from Tom: the shared Codex server restarts in a few minutes. Reply with the word ready and stop."')"
expect stop-asking-is-not-stop lacks 'asked you to stop' "$(prompt s2 '"stop asking me questions and just ship it"')"
for _ in 1 2 3 4; do post s1 "$game" '"git add -A"' 0 | run >/dev/null; done
expect fifth-command fires 'Reply ready now' "$(post s1 "$game" '"git commit -m wip"' 0)"
expect sixth-command quiet '' "$(post s1 "$game" '"git push"' 0)"
expect goal-reprompt-holds-stop fires 'outranks the goal' "$(prompt s1 '"<codex_internal_context source=\"goal\"> Continue working toward the active thread goal."')"
expect goal-reprompt-without-stop quiet '' "$(prompt s3 '"<codex_internal_context source=\"goal\"> Continue working toward the active thread goal."')"
prompt s1 '"restarted, resume from the roadmap restart list"' | run >/dev/null
for _ in 1 2 3 4; do post s1 "$game" '"bun run build"' 0 | run >/dev/null; done
expect cleared-by-next-prompt quiet '' "$(post s1 "$game" '"bun run build:map"' 0)"

# Other tools skip the interpreter; the off switch and malformed input allow.
expect other-tool quiet '' '{"hook_event_name":"PreToolUse","session_id":"x","tool_name":"apply_patch","tool_input":{"command":"bun test"}}'
out="$(prompt k1 '"stop asking, wtf"' | AGENT_NO_AUTHORING_HOOKS=1 "$HOOK" 2>/dev/null)"
if [ -z "$out" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL killswitch"; fi
expect malformed quiet '' 'not json'

printf 'codex-behavior-guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
