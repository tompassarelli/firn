#!/usr/bin/env bash
# Adversarial matrix for native-agent redirect + Gaffer worker topology.
# Commands are hook payload fixtures only; this test never executes them.
# shellcheck disable=SC2016,SC2088
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
HOOK="$HERE/agent-spawn-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/agent-spawn-guard-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/home/.claude" "$SCRATCH/home/.local/state/north"
mkdir -p "$SCRATCH/home/code/gaffer/agents"
printf '%s\n' '<!-- GAFFER_ROUTING {"role":"integrator","taskGrade":"senior","domainRequirements":[],"topology":"worker","tier":"senior","reasoning":"high","posture":"deliver","composition":{"kind":"preset","id":"integrator","overrides":[]}} -->' \
  >"$SCRATCH/home/code/gaffer/agents/integrator.md"
printf '%s\n' '<!-- GAFFER_ROUTING {"role":"integrator","taskGrade":"senior","domainRequirements":[],"topology":"worker","tier":"senior","reasoning":"high","posture":"deliver","composition":{"kind":"preset","id":"integrator","overrides":[]}} -->' \
  >"$SCRATCH/home/code/gaffer/agents/role-mismatch.md"
printf '%s\n' '<!-- GAFFER_ROUTING {"role":"missing-reasoning","taskGrade":"senior","domainRequirements":[],"topology":"worker","tier":"senior","posture":"deliver","composition":{"kind":"preset","id":"missing-reasoning","overrides":[]}} -->' \
  >"$SCRATCH/home/code/gaffer/agents/missing-reasoning.md"
printf '%s\n' '<!-- GAFFER_ROUTING {"role":"researcher","taskGrade":"senior","domainRequirements":[],"topology":"worker","tier":"senior","reasoning":"high","posture":"deliver","composition":{"kind":"preset","id":"researcher","overrides":[]}} -->' \
  >"$SCRATCH/home/code/gaffer/agents/researcher.md"

pass=0 fail=0
set_state() { printf 'dispatch=%s\nguards=%s\n' "$1" "$2" >"$SCRATCH/home/.local/state/north/harness.conf"; }
set_state north on

# run EXPECT DESCRIPTION TOPOLOGY TOOL PAYLOAD [ENV]
# EXPECT: allow | deny | warn. TOPOLOGY: worker | orchestrator | unset.
run() {
  local expect="$1" desc="$2" topology="$3" tool="$4" payload="$5" extra="${6:-}"
  local input out decision context ok=0
  if [[ "$tool" =~ ^(Bash|shell|exec_command)$ ]]; then
    input="$(jq -nc --arg t "$tool" --arg c "$payload" --arg d "$REPO" \
      '{tool_name:$t,tool_input:{command:$c},cwd:$d}')"
  else
    input="$(jq -nc --arg t "$tool" --arg p "$payload" \
      '{tool_name:$t,tool_input:{subagent_type:"general-purpose",prompt:$p}}')"
  fi

  set -- env -u AGENT_TOPOLOGY -u AGENT_NO_AUTHORING_HOOKS -u CLAUDE_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home"
  [ "$topology" = unset ] || set -- "$@" "AGENT_TOPOLOGY=$topology"
  [ -z "$extra" ] || set -- "$@" "$extra"
  out="$(printf '%s' "$input" | "$@" "$HOOK" 2>&1)"
  decision="$(jq -r '.hookSpecificOutput.permissionDecision // "silent"' <<<"${out:-null}" 2>/dev/null || printf malformed)"
  context="$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"${out:-null}" 2>/dev/null || true)"
  case "$expect" in
    deny)  [ "$decision" = deny ] && ok=1 ;;
    allow) [ "$decision" != deny ] && [ "$decision" != malformed ] && ok=1 ;;
    warn)  [ "$decision" = allow ] && [[ "$context" == *'north config dispatch = warn'* ]] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %-5s  %s\n' "$expect" "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-5s  %s\n      topology=%s tool=%s payload=%s\n      decision=%s out=%s\n' \
      "$expect" "$desc" "$topology" "$tool" "$payload" "$decision" "$out"
  fi
}

echo '== worker: North lane creation and peer control are denied =='
run deny 'PATH north spawn' worker Bash 'north spawn implementer "do work"'
run deny 'PATH north delegate' worker Bash 'north delegate "do work"'
run deny 'PATH north steer' worker Bash 'north steer lane-123 "change course"'
run deny 'PATH north retask' worker Bash 'north retask lane-123 "new goal"'
run deny 'absolute North wrapper' worker Bash '/home/tom/code/north/bin/north spawn verifier "check it"'
run deny 'tilde North wrapper' worker Bash '~/code/north/bin/north delegate "check it"'
run deny 'HOME North wrapper' worker Bash '$HOME/code/north/bin/north spawn verifier "check it"'
run deny 'North wrapper behind Bash' worker Bash 'bash ~/code/north/bin/north spawn verifier "check it"'
run deny 'native MCP command surface' worker Bash 'mcp__north__spawn "do work"'
run deny 'direct Gaffer CLI spawn' worker Bash 'bb /home/tom/code/north/cli/agents-cli.clj spawn designer "design"'
run deny 'repo-relative Gaffer CLI spawn' worker Bash 'bb cli/agents-cli.clj spawn designer "design"'
run deny 'direct Gaffer CLI retask' worker Bash 'bb ~/code/north/cli/agents-cli.clj retask lane-1 "new goal"'
run deny 'direct SDK spawn entrypoint' worker Bash 'bun run /home/tom/code/north/sdk/src/spawn.ts "do work"'
run deny 'direct SDK dispatch entrypoint' worker Bash 'bun /home/tom/code/north/sdk/src/dispatch.ts thread-1'
run deny 'repo-relative SDK spawn entrypoint' worker Bash 'bun run sdk/src/spawn.ts "do work"'
run deny 'direct command-envelope peer control' worker Bash 'bb ~/code/north/cli/msg-cli.clj 7977 send-cmd me lane-1 spawn "{:prompt \"x\"}"'
run deny 'worker cannot disable its own guards' worker Bash 'north config guards off'
run deny 'worker cannot weaken dispatch policy' worker Bash 'env north config dispatch native'
run deny 'worker cannot mutate routing policy' worker Bash 'north config routing mode preferential'
run deny 'direct config CLI cannot disable guards' worker Bash 'bb ~/code/north/cli/config-cli.clj guards off'
run allow 'ordinary North message remains available' worker Bash 'bb ~/code/north/cli/msg-cli.clj 7977 send me lane-1 progress "done"'
run allow 'spawn dry-run composes but does not launch' worker Bash 'north spawn integrator "probe" --dry-run'
run allow 'steer dry-run does not command peer' worker Bash 'north steer lane-1 "probe" --dry-run'
run deny 'retask has no dry-run contract' worker Bash 'north retask lane-1 "probe" --dry-run'
run allow 'North config report remains available' worker Bash 'north config'
run allow 'North guard status remains available' worker Bash 'north config guards'
run allow 'North routing report remains available' worker Bash 'north config routing show'

echo '== worker: obvious provider-native agent turns are denied =='
run deny 'Codex exec work turn' worker Bash 'codex exec "implement this"'
run deny 'Codex exec alias work turn' worker Bash 'codex e "implement this"'
run deny 'Codex review work turn' worker Bash '/run/current-system/sw/bin/codex review --uncommitted'
run deny 'Codex resume work turn through env' worker Bash 'env FOO=1 codex resume --last "continue work"'
run deny 'Codex fork work turn through command' worker Bash 'command codex fork --last'
run deny 'Codex global options before exec' worker Bash 'codex -C /tmp --model gpt-5.6-sol exec --json -'
run deny 'Codex bare initial prompt' worker Bash 'codex "implement this"'
run deny 'Codex initial prompt after global options' worker Bash 'codex -C /tmp --model gpt-5.6-sol "implement this"'
run deny 'Codex absolute path initial prompt' worker Bash '/run/current-system/sw/bin/codex "implement this"'
run deny 'Codex cloud task submission' worker Bash 'codex cloud exec --env ENV1 "implement this"'
run deny 'Codex sandbox cannot hide North spawn' worker Bash 'codex sandbox -- north spawn implementer "work"'
run deny 'Codex app-server cannot expose agent backend' worker Bash 'codex app-server --listen stdio://'
run deny 'Codex MCP server cannot expose agent backend' worker Bash 'codex mcp-server'
run deny 'Codex debug app-server cannot send agent message' worker Bash 'codex debug app-server send-message-v2 "work"'
run deny 'Claude print prompt' worker Bash 'claude -p "implement this"'
run deny 'Claude print stdin turn' worker Bash 'claude --print'
run deny 'Claude continue prompt' worker Bash 'claude --continue "continue work"'
run deny 'Claude resume prompt' worker Bash 'claude --resume session-id "continue work"'
run deny 'Claude resume= form with prompt' worker Bash 'claude --resume=session-id "continue work"'
run deny 'Claude bare initial prompt' worker Bash 'claude "implement this"'
run deny 'Claude initial prompt after global options' worker Bash 'claude --model opus --effort high "implement this"'
run deny 'Claude absolute path initial prompt' worker Bash '/run/current-system/sw/bin/claude "implement this"'
run deny 'Claude cloud multi-agent review' worker Bash 'claude ultrareview main'
run deny 'Claude auto-mode AI critique' worker Bash 'claude auto-mode critique --model opus'
run deny 'Claude interactive background-agent view' worker Bash 'claude agents'
run deny 'Claude MCP server cannot expose agent backend' worker Bash 'claude mcp serve'
run deny 'Claude plugin AI eval' worker Bash 'claude plugin eval ./plugin'
run allow 'Codex exec help probe' worker Bash 'codex exec --help'
run allow 'Codex review help probe' worker Bash 'codex review -h'
run allow 'Codex sandbox help probe' worker Bash 'codex sandbox --help'
run allow 'Codex version probe' worker Bash 'codex --version'
run deny 'Codex promptless interactive launch' worker Bash 'codex'
run deny 'Codex promptless launch with model' worker Bash 'codex --model gpt-5.6-sol'
run allow 'Codex features diagnostic' worker Bash 'codex features list'
run allow 'Codex MCP diagnostic' worker Bash 'codex mcp list'
run allow 'Codex login diagnostic' worker Bash 'codex login status'
run allow 'Codex debug model diagnostic' worker Bash 'codex debug models'
run allow 'Claude version probe' worker Bash 'claude --version'
run deny 'Claude promptless interactive launch' worker Bash 'claude'
run deny 'Claude promptless launch with model' worker Bash 'claude --model opus'
run allow 'Claude auth diagnostic' worker Bash 'claude auth status'
run allow 'Claude status diagnostic' worker Bash 'claude status'
run allow 'Claude auto-mode config diagnostic' worker Bash 'claude auto-mode config'
run allow 'Claude auto-mode critique help' worker Bash 'claude auto-mode critique --help'
run allow 'Claude background-agent roster query' worker Bash 'claude agents --json'
run allow 'Claude MCP configuration query' worker Bash 'claude mcp list'
run allow 'Claude plugin inventory query' worker Bash 'claude plugin list'
run allow 'Claude print help probe' worker Bash 'claude -p --help'
run deny 'Claude resume session without prompt' worker Bash 'claude --resume session-id'
run deny 'Claude resume session with model option' worker Bash 'claude --model opus --resume session-id'
run deny 'Claude continue session without prompt' worker Bash 'claude --continue'

echo '== command-position anchoring and compound shell syntax =='
run deny 'spawn after && separator' worker Bash 'printf ready && north spawn executor "work"'
run deny 'delegate after || separator' worker Bash 'false || north delegate "work"'
run deny 'guard mutation after separator' worker Bash 'north show thread-1; north config guards off'
run deny 'spawn after pipeline' worker Bash 'printf prompt | codex exec -'
run deny 'spawn on next line' worker Bash $'printf ready\nnorth spawn executor "work"'
run deny 'spawn in command substitution' worker Bash 'printf "%s" "$(north spawn executor work)"'
run allow 'single-quoted substitution text is prose' worker Bash "printf '%s' '\$(north spawn executor work)'"
run deny 'spawn in explicit shell -c' worker Bash 'bash -c "north spawn executor work"'
run deny 'spawn in login-shell option cluster' worker Bash 'bash -lc "north spawn implementer work"'
run deny 'delegate in errexit-shell option cluster' worker Bash 'bash -ec "north delegate work"'
run deny 'provider turn in trace-shell option cluster' worker Bash 'sh -xc "codex exec work"'
run deny 'guard mutation in wrapped login shell' worker Bash 'env bash -lc "north config guards off"'
run deny 'spawn in timeout-wrapped login shell' worker Bash 'timeout 5s bash -lc "north spawn implementer work"'
run deny 'provider turn in sudo-wrapped shell cluster' worker Bash 'sudo -u tom sh -ec "codex exec work"'
run deny 'fish long command option' worker Bash 'fish --command "north spawn implementer work"'
run deny 'fish init command cannot spawn' worker Bash 'fish -C "north spawn implementer work" -c "echo safe"'
run deny 'fish long init command cannot spawn' worker Bash 'fish --init-command "north spawn implementer work" --command "echo safe"'
run deny 'fish attached init command cannot spawn' worker Bash 'fish --init-command="north spawn implementer work" --command="echo safe"'
run allow 'fish safe init and command remain available' worker Bash 'fish -C "echo setup" -c "echo safe"'
run deny 'env split string cannot spawn' worker Bash 'env -S "north spawn implementer work"'
run deny 'env attached split string cannot spawn' worker Bash 'env --split-string="north spawn implementer work"'
run deny 'env split string cannot hide shell spawn' worker Bash 'env -S "bash -lc '\''north spawn implementer work'\''"'
run deny 'env clustered split string cannot spawn' worker Bash 'env -iS "north spawn implementer work"'
run deny 'env argv0 before split string cannot spawn' worker Bash 'env -a disguised -S "north spawn implementer work"'
run deny 'env unset before split string cannot spawn' worker Bash 'env --unset FOO --split-string="north spawn implementer work"'
run allow 'env value option before safe split remains available' worker Bash 'env -C /tmp -S "printf ready"'
run deny 'env clustered unset value cannot hide spawn' worker Bash 'env -iu FOO north spawn implementer work'
run allow 'env split string safe command remains available' worker Bash 'env -S "printf ready"'
run deny 'env argv0 value cannot hide spawn' worker Bash 'env -a disguised north spawn implementer work'
run deny 'env long argv0 value cannot hide spawn' worker Bash 'env --argv0 disguised north spawn implementer work'
run allow 'env argv0 safe command remains available' worker Bash 'env -a disguised printf ready'
run deny 'exec argv0 value cannot hide spawn' worker Bash 'exec -a disguised north spawn implementer work'
run deny 'exec clustered argv0 value cannot hide spawn' worker Bash 'exec -ca disguised north spawn implementer work'
run allow 'exec argv0 safe command remains available' worker Bash 'exec -a disguised printf ready'
run deny 'sudo timeout value cannot hide spawn' worker Bash 'sudo -T 30 north spawn implementer work'
run deny 'sudo clustered user value cannot hide spawn' worker Bash 'sudo -nu tom north spawn implementer work'
run allow 'sudo clustered user safe command remains available' worker Bash 'sudo -nu tom printf ready'
run allow 'sudo timeout safe command remains available' worker Bash 'sudo -T 30 printf ready'
run deny 'time format value cannot hide spawn' worker Bash '/run/current-system/sw/bin/time -f elapsed north spawn implementer work'
run deny 'time long format value cannot hide spawn' worker Bash '/run/current-system/sw/bin/time --format elapsed north spawn implementer work'
run deny 'time output value cannot hide spawn' worker Bash '/run/current-system/sw/bin/time -o /tmp/timing north spawn implementer work'
run deny 'time clustered format value cannot hide spawn' worker Bash '/run/current-system/sw/bin/time -vf elapsed north spawn implementer work'
run allow 'time format safe command remains available' worker Bash '/run/current-system/sw/bin/time --format=elapsed printf ready'
run allow 'time output safe command remains available' worker Bash '/run/current-system/sw/bin/time --output=/tmp/timing printf ready'
run deny 'timeout clustered kill-after cannot hide spawn' worker Bash 'timeout -vk 1 5 north spawn implementer work'
run allow 'timeout clustered kill-after safe command remains available' worker Bash 'timeout -vk 1 5 printf ready'
run allow 'diagnostic in login-shell option cluster' worker Bash 'bash --noprofile -lc "codex --version"'
run allow 'quoted prose in login-shell option cluster' worker Bash 'bash -lc "echo '\''north spawn implementer work'\''"'
run allow 'uppercase shell flag is not command-string mode' worker Bash 'bash -C ./agent-spawn-guard.test.sh'
run deny 'spawn behind env + command wrappers' worker Bash 'env FOO=1 command north spawn executor work'
run deny 'spawn behind sudo wrapper' worker Bash 'sudo -u tom north delegate work'
run deny 'spawn behind timeout wrapper' worker Bash 'timeout 5s codex exec work'
run deny 'spawn in if body' worker Bash 'if true; then north spawn executor work; fi'
run deny 'spawn in brace group' worker Bash '{ north spawn executor work; }'
run allow 'quoted North example is prose' worker Bash 'echo "north spawn executor work"'
run allow 'single-quoted delegate example is prose' worker Bash "printf '%s\\n' 'north delegate work'"
run allow 'rg pattern mention is prose' worker Bash "rg -n 'codex exec|claude -p|north spawn' ."
run allow 'Python test literal is an argument' worker Bash 'python3 -c '\''assert "north spawn" == "north spawn"'\'''
run allow 'test script path does not reveal its contents' worker Bash 'bash ./agent-spawn-guard.test.sh'
run allow 'North show remains available' worker Bash 'north show thread-1'
run allow 'North tell remains available' worker Bash 'north tell thread-1 progress done'
run allow 'North capture remains available' worker Bash 'north capture "an idea"'
run allow 'North clock remains available' worker Bash 'north clock status'
run allow 'North status/help diagnostics remain available' worker Bash 'north agents && north providers && north --help'

echo '== topology boundary and dispatch-mode independence =='
run allow 'orchestrator may create North lane' orchestrator Bash 'north spawn implementer work'
run allow 'orchestrator may run provider agent' orchestrator Bash 'codex exec work'
run allow 'orchestrator may open provider session' orchestrator Bash 'claude'
run allow 'native/unmanaged session has no topology restriction' unset Bash 'north delegate work'
run allow 'native/unmanaged session may open provider session' unset Bash 'codex'
run allow 'non-Bash tool is not topology shell surface' worker Read 'north spawn implementer work'
set_state native on
run deny 'dispatch=native does not waive worker topology' worker Bash 'north spawn implementer work'
run allow 'dispatch=native preserves native Agent allowance' unset Agent 'native work'
set_state warn on
run warn 'dispatch=warn preserves native Agent nudge' unset Task 'native work'
set_state north on
run deny 'dispatch=north preserves native Agent redirect' unset Agent 'native work'

echo '== native Gaffer redirect preserves the complete routing contract =='
routing_input="$(jq -nc --arg d "$REPO" '{
  tool_name:"Agent",
  tool_input:{subagent_type:"gaffer:integrator",prompt:"integrate the seam"},
  cwd:$d
}')"
routing_out="$(printf '%s' "$routing_input" | env \
  HOME="$SCRATCH/home" \
  "$HOOK" 2>&1)"
routing_reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$routing_out")"
routing_json="$(printf '%s' "$routing_reason" | python3 -c '
import json, sys
text = sys.stdin.read()
marker = "mcp__north__spawn "
start = text.index(marker) + len(marker)
value, _ = json.JSONDecoder().raw_decode(text[start:])
print(json.dumps(value, separators=(",", ":")))
')"
if jq -e '
  keys == ["composition","domainRequirements","posture","prompt","provider","reasoning","role","taskGrade","tier","topology"] and
  .prompt == "<paste the same prompt verbatim>" and .provider == "auto" and
  .role == "integrator" and .taskGrade == "senior" and
  .domainRequirements == [] and .topology == "worker" and
  .tier == "senior" and .reasoning == "high" and .posture == "deliver" and
  .composition == {kind:"preset",id:"integrator",overrides:[]}
' <<<"$routing_json" >/dev/null; then
  pass=$((pass + 1)); echo 'PASS  route  generated Gaffer redirect carries all eight semantic fields'
else
  fail=$((fail + 1)); printf 'FAIL  route  generated Gaffer redirect dropped or changed routing fields\n      out=%s\n' "$routing_out"
fi

invalid_routes_ok=1
for invalid_role in role-mismatch missing-reasoning researcher ../integrator; do
  invalid_input="$(jq -nc --arg d "$REPO" --arg r "gaffer:$invalid_role" '{
    tool_name:"Agent", tool_input:{subagent_type:$r,prompt:"probe"}, cwd:$d
  }')"
  invalid_out="$(printf '%s' "$invalid_input" | env HOME="$SCRATCH/home" "$HOOK" 2>&1)"
  invalid_reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$invalid_out")"
  [[ "$invalid_reason" != *'mcp__north__spawn {'* ]] || invalid_routes_ok=0
done
if [[ "$invalid_routes_ok" -eq 1 ]]; then
  pass=$((pass + 1)); echo 'PASS  route  malformed, mismatched, retired, and hostile Gaffer IDs fail closed'
else
  fail=$((fail + 1)); echo 'FAIL  route  an invalid Gaffer marker produced a callable North envelope'
fi

echo '== shared kill-switch semantics =='
run allow 'AGENT_NO_AUTHORING_HOOKS kills worker guard' worker Bash 'north spawn implementer work' AGENT_NO_AUTHORING_HOOKS=1
run allow 'legacy Claude alias kills worker guard' worker Bash 'north spawn implementer work' CLAUDE_NO_AUTHORING_HOOKS=1
set_state north off
run allow 'persistent guards=off kills worker guard' worker Bash 'north spawn implementer work'
run deny 'AGENT_NO_AUTHORING_HOOKS=0 forces live over state' worker Bash 'north spawn implementer work' AGENT_NO_AUTHORING_HOOKS=0
set_state north on

echo '== Claude user hook + Codex managed-hook parity =='
if jq -e '
  [.hooks.PreToolUse[]? |
   select((.matcher // "") | test("(^|[|])Bash([|]|$)")) |
   .hooks[]? |
   select(.type == "command" and (.command | endswith("/agent-spawn-guard.sh")))] |
  length == 1
' "$REPO/dotfiles/claude/settings.json" >/dev/null; then
  pass=$((pass + 1)); echo 'PASS  bind   Claude Bash matcher has one canonical worker guard'
else
  fail=$((fail + 1)); echo 'FAIL  bind   Claude Bash matcher worker guard missing/duplicated'
fi

if jq -e '
  [.hooks.PreToolUse[]? |
   select((.matcher // "") | test("(^|[|])Bash([|]|$)")) |
   .hooks[]? |
   select(.type == "command" and (.command | endswith("/agent-spawn-guard.sh")))] |
  length == 0
' "$REPO/dotfiles/codex/hooks.json" >/dev/null &&
  python3 - "$REPO/modules/codex/requirements.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as handle:
    policy = tomllib.load(handle)
assert set(policy) == {
    "allow_managed_hooks_only",
    "allow_remote_control",
    "features",
    "hooks",
}
assert type(policy["allow_managed_hooks_only"]) is bool
assert policy["allow_managed_hooks_only"] is True
assert type(policy["allow_remote_control"]) is bool
assert policy["allow_remote_control"] is False
assert policy["features"] == {"hooks": True}
hooks = policy["hooks"]
assert set(hooks) == {
    "managed_dir",
    "SessionStart",
    "SubagentStart",
    "PreToolUse",
    "PostToolUse",
    "Stop",
}
assert hooks["managed_dir"] == "/etc/codex/hooks"
bindings = [
    binding
    for binding in hooks["PreToolUse"]
    if binding.get("matcher") == "^Bash$"
]
assert len(bindings) == 1
commands = [
    command
    for command in bindings[0]["hooks"]
    if command.get("command", "").endswith("/agent-spawn-guard.sh")
]
assert len(commands) == 1
command = commands[0]
assert command == {
    "type": "command",
    "command": (
        "/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV "
        "/etc/codex/hooks/runtime/bash /etc/codex/hooks/agent-spawn-guard.sh"
    ),
    "timeout": 10,
}
PY
then
  pass=$((pass + 1)); echo 'PASS  bind   Codex authoritative managed policy has one Bash worker guard'
else
  fail=$((fail + 1)); echo 'FAIL  bind   Codex managed policy or Bash worker guard differs from its authoritative contract'
fi

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
