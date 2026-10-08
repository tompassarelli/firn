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
expect unchanged-rerun fires 'already passed' "$(pre b1 "$game" '"bun test"')"
expect rerun-lists-cases fires 'Which case is it' "$(pre b1 "$game" '"bun test"')"
expect rerun-confidence-stops fires 'Case C stops' "$(pre b1 "$game" '"CASE=C FACT=\"land it after one more pass\" bun test"')"
expect rerun-banned-fact fires "rest on" "$(pre b1 "$game" '"CASE=A FACT=\"to be sure nothing regressed\" bun test"')"
expect rerun-short-fact fires '15 or more' "$(pre b1 "$game" '"CASE=A FACT=\"map\" bun test"')"
expect rerun-unasked-b fires 'needs Tom' "$(pre b1 "$game" '"CASE=B FACT=\"x\" bun test"')"
expect rerun-e-needs-tee fires 'tee FILE' "$(pre b1 "$game" '"CASE=E FACT=\"output scrolled out of the window\" bun test"')"
expect rerun-case-a quiet '' "$(pre b1 "$game" '"CASE=A FACT=\"rebuilt map at 18:02 from the new model import\" bun test"')"
expect rerun-one-justification fires 'one justification' "$(pre b1 "$game" '"CASE=A FACT=\"another rebuilt map from the other import\" bun test"')"
grep -q '"gate": "rerun"' "$scratch/state/verify-overrides.jsonl" && pass=$((pass + 1)) || { fail=$((fail + 1)); echo 'FAIL override-logged'; }
expect other-command quiet '' "$(pre b1 "$game" '"git status"')"
printf 'b\n' >>"$game/arc.ts"
expect changed-code quiet '' "$(pre b1 "$game" '"bun test"')"
post b1 "$game" '"bun test"' 1 | run >/dev/null
expect after-failure quiet '' "$(pre b1 "$game" '"bun test"')"
post b1 "$game" '"cd ts && bun run check"' 0 | run >/dev/null
expect chained-check-rerun fires 'already passed' "$(pre b1 "$game" '"cd ts && bun run check"')"

# One run per check per commit, across every agent: a farm run that passed on
# this commit is refused to any other worker; one case-F timing confirmation passes.
farm="$code/wisp/main"
mkdir -p "$farm" && git -C "$farm" init -q && printf 'a\n' >"$farm/a.ts" && git -C "$farm" add a.ts \
  && git -C "$farm" -c user.name=t -c user.email=t@t commit -qm init
expect farm-first-run quiet '' "$(pre f1 "$farm" '"bun wisp farm balance \"wren expert 120\" --wait"')"
post f1 "$farm" '"bun wisp farm balance \"wren expert 120\" --wait"' 0 | run >/dev/null
expect farm-repeat-other-worker fires 'already passed on this code' "$(pre f2 "$farm" '"cd ts && bun wisp farm balance \"wren expert 120\""')"
expect farm-other-spec quiet '' "$(pre f2 "$farm" '"bun wisp farm balance \"wren expert 40\" --wait"')"
post f1 "$farm" '"bun wisp farm perf \"profile four\""' 0 | run >/dev/null
expect timing-without-lease fires 'exclusive capacity lease' "$(pre f2 "$farm" '"CASE=F FACT=\"first run shared the box with a 99 load\" bun wisp farm perf \"profile four\""')"
expect timing-confirm quiet '' "$(pre f2 "$farm" '"CASE=F FACT=\"first run shared the box with a 99 load\" bun machine-capacity.mjs run --class exclusive -- bun wisp farm perf \"profile four\""')"
saved_path="$PATH"; mkdir -p "$scratch/bin" && printf '#!/bin/sh\necho success\n' >"$scratch/bin/gh" && chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"
expect rerun-passing-run fires 'already passed' "$(pre r1 "$farm" '"gh run rerun 37752983299"')"
printf '#!/bin/sh\necho failure\n' >"$scratch/bin/gh"
expect rerun-failed-run quiet '' "$(pre r1 "$farm" '"gh run rerun 37752983299"')"
export PATH="$saved_path"

# A passing check on unlanded code: land it. The nudge repeats after three idle commands,
# and the turn can't end until it lands.
post l1 "$game" '"bun test -t arc"' 0 | run >/dev/null
expect land-nudge fires 'safe-push' "$(post l2 "$game" '"bun test -t jump"' 0)"
post l2 "$game" '"ls"' 0 | run >/dev/null; post l2 "$game" '"ls"' 0 | run >/dev/null
expect land-nudge-repeat fires 'still nothing landed' "$(post l2 "$game" '"ls"' 0)"
stop_in() { printf '{"hook_event_name":"Stop","session_id":"%s","stop_hook_active":false,"last_assistant_message":%s}' "$1" "$2"; }
expect stop-unlanded fires "isn't landed" "$(stop_in l2 '"Tests pass on the arc fix.\nNeeds you: nothing"')"
expect stop-blocked-ok quiet '' "$(stop_in l2 '"Blocked: safe-push failed with exit code 1: main moved.\nNeeds you: nothing"')"

# Measuring: after two measurements with no change, a third needs a box or a fix.
for i in 1 2; do post s1 "$game" '"hyperfine \"node arc.js\""' 0 | run >/dev/null; done
expect third-measure fires 'Which case is it' "$(pre s1 "$game" '"hyperfine \"node arc.js\""')"
expect measure-understand fires 'Case C stops' "$(pre s1 "$game" '"CASE=C FACT=\"see which phase dominates\" hyperfine \"node arc.js\""')"
expect measure-box-prefix fires 'starts `box:`' "$(pre s1 "$game" '"CASE=A FACT=\"p99 for the phase table\" hyperfine \"node arc.js\""')"
expect measure-fix-baseline quiet '' "$(pre s1 "$game" '"CASE=B FACT=\"fix: replay recorded CPU inputs during resim\" hyperfine \"node arc.js\""')"
expect measure-needs-patch fires 'patch in between' "$(pre s1 "$game" '"hyperfine \"node arc.js\""')"
patch_done() { printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch"},"tool_response":"ok"}' "$1" "$2"; }
patch_done s1 "$game" | run >/dev/null
expect measure-after-patch quiet '' "$(pre s1 "$game" '"hyperfine \"node arc.js\""')"

# Briefs: a measure-only worker must end with a landed fix or a PEER line.
brief() { printf '{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"%s","tool_name":"collaborationspawn_agent","tool_input":{"task_name":"perf","message":%s}}' "$game" "$1"; }
expect measure-only-brief fires 'only measures' "$(brief '"Item: smashcraft#168. MEASURE ONLY: per-phase p99 table. No fix in that task."')"
expect measure-then-fix quiet '' "$(brief '"Item: smashcraft#168. Measure only the worst tape, then land the fix it points to, or post PEER."')"
expect ordinary-brief quiet '' "$(brief '"Item: smashcraft#273. Narrow Archer side special to 3-15% use and land it."')"

# New manifest, provenance, checksum or similar files in a prototype repo need Tom's ask.
add() { printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\\n*** Add File: %s\\n+x\\n*** End Patch"}}' "$1" "$2" "$3"; }
expect checksum-file fires 'Which case is it' "$(add m1 "$game" evidence/perf-168/tapes.sha256)"
expect changelog-file fires 'CHANGELOG file' "$(add m1 "$game" CHANGELOG.md)"
expect source-file quiet '' "$(add m1 "$game" ts/src/arc.ts)"
expect tooling-manifest quiet '' "$(add m1 "$code/north/main" manifest.json)"
expect shell-checksum fires 'sha256' "$(pre m1 "$game" '"sha256sum build/*.lua > evidence/tapes.sha256"')"
expect justify-traceability fires 'Case C stops' "$(pre m1 "$game" '": justify scaffold C \"keeps the tapes traceable later\""')"
expect justify-banned fires 'rest on' "$(pre m1 "$game" '": justify scaffold B \"safety net for the next worker\""')"
expect justify-build quiet '' "$(pre m1 "$game" '": justify scaffold B \"bun wisp map build fails: missing build/manifest.json\""')"
expect justified-patch quiet '' "$(add m1 "$game" build/manifest.json)"
expect justification-used fires 'Which case' "$(add m1 "$game" build/other-manifest.json)"
prompt m2 '"add a build manifest that lists every imported model"' | run >/dev/null
expect asked-manifest quiet '' "$(add m2 "$game" build/manifest.json)"

# An issue whose boxes are all ticked gets closed now.
expect all-ticked fires 'Close it now' "$(post t1 "$game" '"gh issue edit 5 --body \"## Done when\n- [x] a\n- [x] b\""' 0)"
expect box-open quiet '' "$(post t1 "$game" '"gh issue edit 5 --body \"## Done when\n- [x] a\n- [ ] b\""' 0)"

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

# An orchestrator hands worker jobs to workers; landing must account for the issue box.
spawn() { printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":{},"tool_response":"{}"}' "$1" "$2" "$3"; }
expect solo-runs-tests quiet '' "$(pre o1 "$game" '"bun test"')"
spawn o1 "$game" collaborationspawn_agent | run >/dev/null
expect orchestrator-runs-tests fires 'orchestrating 1 workers' "$(pre o1 "$game" '"bun test"')"
expect orchestrator-digs-logs fires "worker's job" "$(pre o1 "$game" '"rg -n error /tmp/smashcraft-ci-37620992094.log"')"
expect orchestrator-reads-ci fires "worker's job" "$(pre o1 "$game" '"gh run view 37620992094 --repo tompassarelli/smashcraft --log-failed"')"
expect orchestrator-closes-issue quiet '' "$(pre o1 "$game" '"gh issue close 184 --repo tompassarelli/smashcraft"')"
expect orchestrator-lands quiet '' "$(pre o1 "$game" '"git -C ~/code/smashcraft/main merge --ff-only native_r2"')"
worker_pre() { printf '{"hook_event_name":"PreToolUse","session_id":"%s","agent_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' "$1" "$2" "$3" "$4"; }
expect worker-of-orchestrator-runs-tests quiet '' "$(worker_pre o1 capture_r2 "$game" '"bun test"')"
# The root's score counts its workers' closes: the orchestrator closes nothing itself.
printf '{"hook_event_name":"PostToolUse","session_id":"t1","agent_id":"art_r3","cwd":"%s","tool_name":"Bash","tool_input":{"command":"gh issue close 163 167"},"tool_response":"Exit code: 0\\nOutput:\\nok"}' "$game" | run >/dev/null
expect tree-score fires '2 issues closed' "$(prompt t1 '"How is it going?"')"
expect other-tree-score fires '0 issues closed' "$(prompt t2 '"How is it going?"')"
expect orchestrator-with-reason quiet '' "$(pre o1 "$game" '"ORCH_RUNS_BECAUSE=\"all eight workers are mid-native-run\" bun test"')"
expect landed-no-box fires 'closed nothing' "$(stopping false '"Landed 60cacdfe. The original native bot capture completed both matches in 95 seconds; 21 journey tests passed."')"
expect landed-and-closed quiet '' "$(stopping false '"Landed 60cacdfe and closed #144: all 13 fighters show their spell.\nNeeds you: nothing"')"
expect landed-box-remains quiet '' "$(stopping false '"Landed c0de10c6. #181 is at 3/4; the native capture box remains."')"

# A heavy suite already running in the same worktree is not started twice.
suite_dir="$scratch/suite" && mkdir -p "$suite_dir/ts" "$scratch/other"
(cd "$suite_dir/ts" && bash -c 'sleep 30; :' bun scripts/lua-tests.ts) & sleeper=$!
sleep 0.3
expect duplicate-suite fires 'already running' "$(pre d1 "$suite_dir" '"cd ts && bun scripts/lua-tests.ts"')"
expect suite-elsewhere quiet '' "$(pre d1 "$scratch/other" '"bun scripts/lua-tests.ts"')"
expect suite-kill quiet '' "$(pre d1 "$suite_dir" '"pkill -f scripts/lua-tests.ts"')"
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null

# A commander's relay reaches the root session once, after any tool or at Stop.
mkdir -p "$scratch/state"
printf 'Workers blocked on native startup retry now.' >"$scratch/state/relay-rr.txt"
expect relay-skips-worker quiet '' '{"hook_event_name":"PostToolUse","session_id":"rr","agent_id":"capture_r2","tool_name":"collaborationsend_message","tool_input":{},"tool_response":"{}"}'
expect relay-after-any-tool fires 'retry now' '{"hook_event_name":"PostToolUse","session_id":"rr","tool_name":"collaborationsend_message","tool_input":{},"tool_response":"{}"}'
expect relay-delivered-once quiet '' '{"hook_event_name":"PostToolUse","session_id":"rr","tool_name":"collaborationsend_message","tool_input":{},"tool_response":"{}"}'
printf 'Close #163 next.' >"$scratch/state/relay-rr.txt"
expect relay-at-stop fires 'Close #163 next' "$(printf '{"hook_event_name":"Stop","session_id":"rr","stop_hook_active":false,"last_assistant_message":"Done: closed #147.\\nNeeds you: nothing"}')"

# Other tools skip the interpreter; the off switch and malformed input allow.
expect other-tool quiet '' '{"hook_event_name":"PreToolUse","session_id":"x","tool_name":"apply_patch","tool_input":{"command":"bun test"}}'
out="$(prompt k1 '"stop asking, wtf"' | AGENT_NO_AUTHORING_HOOKS=1 "$HOOK" 2>/dev/null)"
if [ -z "$out" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL killswitch"; fi
expect malformed quiet '' 'not json'

printf 'codex-behavior-guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
