#!/usr/bin/env bash
# north-clock-guard.test.sh — hermetic test matrix for north-clock-guard.sh.
# Run after EVERY edit to the hook: ./north-clock-guard.test.sh
# Pipes synthetic PreToolUse hook-input JSON into the hook and asserts the
# decision. FRAM_LOG/FRAM_TELEMETRY_LOG point at fixture files, or HOME points
# at a scratch canonical corpus, so the real ~/.local/state/north logs are NEVER
# read or written. AUTHORING_KILLSWITCH_STATE is likewise scratch-scoped so the
# machine's real kill-switch cannot skew results.
# shellcheck disable=SC2016  # fixtures contain literal $ and shell operators on purpose
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/north-clock-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/clockguard-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

CLIENT_DIR="$HOME/code/client/msa"          # a real-shaped client path (need not exist on disk)
NONCLIENT="$HOME/code/nixos-config"

# ---- fixtures: minimal fact logs in the facts.log line shape --------------
# An OPEN session owned by msa (session_of + start_time, no end_time; thread owner=msa).
cat >"$SCRATCH/open-msa.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@sess-1", :p "session_of", :r "@thread-msa", :by "coord"}
{:tx 3, :op "assert", :l "@sess-1", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

# An OPEN session owned by personal (wrong owner for an msa edit).
cat >"$SCRATCH/open-personal.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-p", :p "owner", :r "personal", :by "coord"}
{:tx 2, :op "assert", :l "@sess-2", :p "session_of", :r "@thread-p", :by "coord"}
{:tx 3, :op "assert", :l "@sess-2", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

# No open session: the msa session was started then STOPPED (end_time present).
cat >"$SCRATCH/closed.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@sess-1", :p "session_of", :r "@thread-msa", :by "coord"}
{:tx 3, :op "assert", :l "@sess-1", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
{:tx 4, :op "assert", :l "@sess-1", :p "end_time", :r "2026-07-15T11:00:00", :by "coord"}
EOF

# Two open sessions: one personal, one msa. ANY matching owner must allow.
cat >"$SCRATCH/two-open.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-p", :p "owner", :r "personal", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 3, :op "assert", :l "@sess-p", :p "session_of", :r "@thread-p", :by "coord"}
{:tx 4, :op "assert", :l "@sess-p", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
{:tx 5, :op "assert", :l "@sess-m", :p "session_of", :r "@thread-msa", :by "coord"}
{:tx 6, :op "assert", :l "@sess-m", :p "start_time", :r "2026-07-15T10:05:00", :by "coord"}
EOF

pass=0 fail=0

# emit_json TOOL FP_OR_CMD CWD  — build a PreToolUse payload for a tool.
emit_json() {
  local tool="$1" arg="$2" cwd="${3:-}"
  if [ "$tool" = Bash ]; then
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$arg" "$cwd"
  else
    python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2]}}))' "$tool" "$arg"
  fi
}

# run EXPECT DESC LOG TOOL ARG [CWD] — EXPECT: allow | deny | mismatch
#   allow    -> exit 0, no deny JSON on stdout
#   deny     -> deny JSON on stdout with permissionDecision deny
#   mismatch -> deny JSON AND the reason names the owner mismatch ("WRONG clock")
run() {
  local expect="$1" desc="$2" log="$3" tool="$4" arg="$5" cwd="${6:-}"
  local json out
  json="$(emit_json "$tool" "$arg" "$cwd")"
  out="$(printf '%s' "$json" | env -u CLAUDE_NO_AUTHORING_HOOKS -u FRAM_TELEMETRY_LOG \
    FRAM_LOG="$SCRATCH/$log" \
    AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
    "$HOOK" 2>/dev/null)"
  local denied=0 mism=0
  case "$out" in *'"permissionDecision": "deny"'*) denied=1 ;; esac
  case "$out" in *'WRONG clock'*) mism=1 ;; esac
  local ok=0
  case "$expect" in
    allow)    [ "$denied" = 0 ] && ok=1 ;;
    deny)     [ "$denied" = 1 ] && ok=1 ;;
    mismatch) [ "$denied" = 1 ] && [ "$mism" = 1 ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %-8s  %s\n' "$expect" "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-8s  %s\n      denied=%s mism=%s  out=%s\n' "$expect" "$desc" "$denied" "$mism" "$out"
  fi
}

echo "== deliverable cases (a)-(g) =="
run deny     '(a) Edit client path, no open session'                closed.log        Edit "$CLIENT_DIR/api.py"
run allow    '(b) Edit client path, open session owner=msa'         open-msa.log      Edit "$CLIENT_DIR/api.py"
run mismatch '(c) Edit client path, open session owner=personal'    open-personal.log Edit "$CLIENT_DIR/api.py"
run deny     '(d) Bash sed -i on client path, no clock'             closed.log        Bash "sed -i s/a/b/ $CLIENT_DIR/api.py"
run allow    '(e) Bash git log, cwd=client (pure read)'             closed.log        Bash "git log --oneline -5" "$CLIENT_DIR"
run allow    '(f) Edit outside client'                              closed.log        Edit "$NONCLIENT/flake.nix"
run allow    '(g) two open sessions, one owner=msa'                 two-open.log      Edit "$CLIENT_DIR/api.py"

echo "== bash mutation heuristic: mutations gated =="
run deny  'redirect > into client file, no clock'   closed.log Bash "echo x > $CLIENT_DIR/out.txt"
run deny  'redirect >> append, no clock'            closed.log Bash "printf y >> $CLIENT_DIR/out.txt"
run deny  'git commit in client cwd, no clock'      closed.log Bash "git commit -m wip" "$CLIENT_DIR"
run deny  'rm in client cwd, no clock'              closed.log Bash "rm -f build.o" "$CLIENT_DIR"
run deny  'cp into client path, no clock'           closed.log Bash "cp /tmp/x $CLIENT_DIR/x"
run deny  'mv in client cwd, no clock'              closed.log Bash "mv a b" "$CLIENT_DIR"
run deny  'tee client file, no clock'               closed.log Bash "echo x | tee $CLIENT_DIR/f"
run deny  'npm install in client cwd, no clock'     closed.log Bash "npm install" "$CLIENT_DIR"
run allow 'git commit in client cwd, clock owner=msa'  open-msa.log Bash "git commit -m done" "$CLIENT_DIR"

echo "== bash mutation heuristic: pure reads never deny =="
run allow 'git status in client cwd'                closed.log Bash "git status" "$CLIENT_DIR"
run allow 'git diff in client cwd'                  closed.log Bash "git diff HEAD~1" "$CLIENT_DIR"
run allow 'grep client file (2>/dev/null stderr)'   closed.log Bash "grep -n foo $CLIENT_DIR/f 2>/dev/null"
run allow 'cat client file'                         closed.log Bash "cat $CLIENT_DIR/README.md"
run allow 'ls client dir'                           closed.log Bash "ls -la" "$CLIENT_DIR"
run allow 'find client dir (no -delete)'            closed.log Bash "find . -name '*.py'" "$CLIENT_DIR"
run allow 'curl GET referencing nothing client'     closed.log Bash "curl -s https://api.github.com" "$CLIENT_DIR"

echo "== command-position anchoring: mutator words in FILENAMES never deny =="
# The confirmed live defect: bare \b verb boundaries matched inside hyphen-/path-
# delimited filename segments, so a pure read from a client cwd got DENIED.
run allow 'EXACT REPRO: pwd && ls -la north-*-guard 2>&1 && git log' closed.log Bash \
  "pwd && ls -la ~/code/north/bin/north-commit-guard ~/code/north/bin/north-install-commit-guard 2>&1 && git -C ~/code/north log --oneline -4" "$CLIENT_DIR"
run allow 'ls path with install/rm/cp/dd/ln in NAMES'   closed.log Bash "ls -la any/path/with-install-rm-cp-dd-ln-in-names" "$CLIENT_DIR"
run allow 'cat file named my-cp-notes.txt'              closed.log Bash "cat ./my-cp-notes.txt" "$CLIENT_DIR"
run allow 'grep -rn pattern . (recursive read)'         closed.log Bash "grep -rn pattern ." "$CLIENT_DIR"
run allow 'read a path segment /x/dd/y.txt'             closed.log Bash "cat /x/dd/y.txt" "$CLIENT_DIR"
run allow 'filename not-git-commit.md in an ls'         closed.log Bash "ls -la not-git-commit.md" "$CLIENT_DIR"
run allow 'bun test (test != run)'                      closed.log Bash "bun test" "$CLIENT_DIR"

echo "== fd-dups / fd-prefixed stderr redirects never deny =="
run allow 'grep with 2>&1 fd-dup'                       closed.log Bash "grep -n foo bar 2>&1" "$CLIENT_DIR"
run allow 'command with >&2 fd-dup'                     closed.log Bash "cat f >&2" "$CLIENT_DIR"
run allow 'grep with 2>/dev/null fd-prefixed stderr'    closed.log Bash "grep -n foo bar 2>/dev/null" "$CLIENT_DIR"

echo "== command-position anchoring: real mutations STILL deny =="
run deny  'sed -i at command position'                  closed.log Bash "sed -i s/a/b/ file.ts" "$CLIENT_DIR"
run deny  'sudo rm (through wrapper)'                    closed.log Bash "sudo rm x" "$CLIENT_DIR"
run deny  'rm after && separator'                        closed.log Bash "foo && rm x" "$CLIENT_DIR"
run deny  'rm piped after |'                             closed.log Bash "true | rm x" "$CLIENT_DIR"
run deny  'echo redirect > file'                        closed.log Bash "echo hi > file" "$CLIENT_DIR"

echo "== cwd-escape: cd to an abs non-client dir attributes THERE, not the session cwd =="
run allow 'cd nixos-config && git stash pop (2026-07-16 repro)' closed.log Bash "cd $NONCLIENT && git stash -q && git stash pop -q" "$CLIENT_DIR"
run allow 'VAR= prefix then cd non-client && git commit'        closed.log Bash "V=1 && cd $NONCLIENT && git commit -m x" "$CLIENT_DIR"
run deny  'cd non-client, client path still in command'         closed.log Bash "cd /tmp && rm -rf $CLIENT_DIR/build" "$CLIENT_DIR"
run deny  'relative cd stays session-attributed'                closed.log Bash "cd sub && git commit -m x" "$CLIENT_DIR"

echo "== fs-mutator with only abs non-client targets acts THERE, not the cwd =="
run allow 'rm abs /run path (stop-hook marker shape, 2026-07-16 repro)' closed.log Bash "rm /run/user/1000/north-delegated/session-x" "$CLIENT_DIR"
run allow 'mkdir -p abs /tmp path'                             closed.log Bash "mkdir -p /tmp/foo/bar" "$CLIENT_DIR"
run deny  'rm relative target stays cwd-gated'                 closed.log Bash "rm -f build.o" "$CLIENT_DIR"
run deny  'compound rm /tmp then git commit stays gated'       closed.log Bash "rm /tmp/x && git commit -m x" "$CLIENT_DIR"

echo "== sed -i anchoring: an i in a hyphenated ARG (nixos-config) never denies =="
run allow 'sed -n read of a nixos-config path (2026-07-16 repro)' closed.log Bash "sed -n '1,80p' $NONCLIENT/dotfiles/agents/hooks/north-clock-guard.sh" "$CLIENT_DIR"
run deny  'sed --in-place still gated'                          closed.log Bash "sed --in-place s/a/b/ f.ts" "$CLIENT_DIR"

echo "== non-client + fail-open =="
run allow 'Bash mutation outside client'            closed.log Bash "rm -rf ./build" "$NONCLIENT"
run allow 'Edit, FRAM_LOG missing -> fail-open'     nonexistent.log Edit "$CLIENT_DIR/api.py"

echo "== canonical split corpus + stale-monolith contradictions =="
DEFAULT_HOME="$SCRATCH/home"
DEFAULT_STATE="$DEFAULT_HOME/.local/state/north"
DEFAULT_REPO="$DEFAULT_HOME/code/client/msa/work"
mkdir -p "$DEFAULT_STATE" "$DEFAULT_REPO"
git -C "$DEFAULT_REPO" init -q -b msa-321-work
git -C "$DEFAULT_REPO" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty --no-verify -qm init

fact() {
  printf '{:tx %s, :op "%s", :l "%s", :p "%s", :r "%s", :by "test"}\n' \
    "$1" "$2" "$3" "$4" "$5"
}
assert_fact() { fact "$1" assert "$2" "$3" "$4"; }

run_default() {
  local json
  json="$(emit_json Edit "$DEFAULT_REPO/api.py")"
  printf '%s' "$json" | env -u CLAUDE_NO_AUTHORING_HOOKS -u FRAM_LOG -u FRAM_TELEMETRY_LOG \
    HOME="$DEFAULT_HOME" AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
    "$HOOK" 2>/dev/null
}

# Stale facts.log says no clock; the live split says an msa clock is open. The
# end_time retraction proves the merge applies exact current-state semantics.
{
  assert_fact 1 '@stale-thread' owner msa
  assert_fact 2 '@stale-thread' linear MSA-321
} > "$DEFAULT_STATE/facts.log"
{
  assert_fact 101 '@live-thread' owner msa
  assert_fact 102 '@live-thread' linear MSA-321
} > "$DEFAULT_STATE/coordination.log"
{
  assert_fact 103 '@live-session' session_of '@live-thread'
  assert_fact 104 '@live-session' start_time '2026-07-16T12:00:00Z'
  assert_fact 105 '@live-session' end_time '2026-07-16T12:01:00Z'
  fact 106 retract '@live-session' end_time '2026-07-16T12:01:00Z'
} > "$DEFAULT_STATE/telemetry.log"
split_out="$(run_default)"
if [[ "$split_out" != *'"permissionDecision": "deny"'* ]]; then
  pass=$((pass + 1)); echo "PASS  allow     split owner + re-opened telemetry session beats stale monolith"
else
  fail=$((fail + 1)); echo "FAIL  allow     split join denied: $split_out"
fi

# The same pair remains selectable explicitly for isolated fixtures/instances.
split_json="$(emit_json Edit "$DEFAULT_REPO/api.py")"
split_override_out="$(printf '%s' "$split_json" | env -u CLAUDE_NO_AUTHORING_HOOKS \
  HOME="$DEFAULT_HOME" FRAM_LOG="$DEFAULT_STATE/coordination.log" \
  FRAM_TELEMETRY_LOG="$DEFAULT_STATE/telemetry.log" \
  AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" "$HOOK" 2>/dev/null)"
if [[ "$split_override_out" != *'"permissionDecision": "deny"'* ]]; then
  pass=$((pass + 1)); echo "PASS  allow     explicit FRAM_LOG + FRAM_TELEMETRY_LOG pair is preserved"
else
  fail=$((fail + 1)); echo "FAIL  allow     explicit split override denied: $split_override_out"
fi

# Reverse the contradiction: stale facts.log has an msa clock, while the live
# split has only a personal clock. The deny hint must use the current live Linear
# link, not the stale monolith or a newer-but-retracted link.
{
  assert_fact 1 '@stale-thread' owner msa
  assert_fact 2 '@stale-thread' linear MSA-321
  assert_fact 3 '@stale-session' session_of '@stale-thread'
  assert_fact 4 '@stale-session' start_time '2026-07-16T11:00:00Z'
} > "$DEFAULT_STATE/facts.log"
{
  assert_fact 201 '@live-thread' owner msa
  assert_fact 202 '@live-thread' linear MSA-321
  assert_fact 203 '@personal-thread' owner personal
  assert_fact 250 '@retracted-thread' linear MSA-321
  fact 251 retract '@retracted-thread' linear MSA-321
} > "$DEFAULT_STATE/coordination.log"
{
  assert_fact 204 '@personal-session' session_of '@personal-thread'
  assert_fact 205 '@personal-session' start_time '2026-07-16T12:30:00Z'
} > "$DEFAULT_STATE/telemetry.log"
split_out="$(run_default)"
if [[ "$split_out" == *'"permissionDecision": "deny"'* &&
      "$split_out" == *'WRONG clock'* &&
      "$split_out" == *'clock start live-thread'* &&
      "$split_out" != *'clock start stale-thread'* &&
      "$split_out" != *'clock start retracted-thread'* ]]; then
  pass=$((pass + 1)); echo "PASS  mismatch  live split verdict + Linear hint ignore stale/retracted links"
else
  fail=$((fail + 1)); echo "FAIL  mismatch  split/hint result: $split_out"
fi

# With the split absent, the legacy monolith remains a supported fallback.
rm -f "$DEFAULT_STATE/coordination.log" "$DEFAULT_STATE/telemetry.log"
{
  assert_fact 301 '@legacy-thread' owner msa
  assert_fact 302 '@legacy-session' session_of '@legacy-thread'
  assert_fact 303 '@legacy-session' start_time '2026-07-16T13:00:00Z'
} > "$DEFAULT_STATE/facts.log"
legacy_out="$(run_default)"
if [[ "$legacy_out" != *'"permissionDecision": "deny"'* ]]; then
  pass=$((pass + 1)); echo "PASS  allow     facts.log fallback applies only when split is absent"
else
  fail=$((fail + 1)); echo "FAIL  allow     legacy fallback denied: $legacy_out"
fi

echo "== kill-switch (env) forces allow =="
ks_json="$(emit_json Edit "$CLIENT_DIR/api.py")"
ks_out="$(printf '%s' "$ks_json" | env CLAUDE_NO_AUTHORING_HOOKS=1 \
  FRAM_LOG="$SCRATCH/closed.log" AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
  "$HOOK" 2>/dev/null)"
case "$ks_out" in
  *'"permissionDecision": "deny"'*) fail=$((fail + 1)); echo "FAIL  killswitch  env CLAUDE_NO_AUTHORING_HOOKS=1 still denied" ;;
  *) pass=$((pass + 1)); echo "PASS  killswitch  env CLAUDE_NO_AUTHORING_HOOKS=1 -> allow" ;;
esac

echo
echo "== result: $pass passed, $fail failed =="
[ "$fail" = 0 ]
