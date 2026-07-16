#!/usr/bin/env bash
# north-clock-guard.test.sh — hermetic test matrix for north-clock-guard.sh.
# Run after EVERY edit to the hook: ./north-clock-guard.test.sh
# Pipes synthetic PreToolUse hook-input JSON into the hook and asserts the
# decision. FRAM_LOG is pointed at fixture files under a scratch dir so the real
# ~/.local/state/north/facts.log is NEVER read or written. AUTHORING_KILLSWITCH_STATE
# is likewise scratch-scoped so the machine's real kill-switch can't skew results.
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
  out="$(printf '%s' "$json" | env -u CLAUDE_NO_AUTHORING_HOOKS \
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
run allow 'sed -n read of a nixos-config path (2026-07-16 repro)' closed.log Bash "sed -n '1,80p' $NONCLIENT/dotfiles/claude/hooks/north-clock-guard.sh" "$CLIENT_DIR"
run deny  'sed --in-place still gated'                          closed.log Bash "sed --in-place s/a/b/ f.ts" "$CLIENT_DIR"

echo "== non-client + fail-open =="
run allow 'Bash mutation outside client'            closed.log Bash "rm -rf ./build" "$NONCLIENT"
run allow 'Edit, FRAM_LOG missing -> fail-open'     nonexistent.log Edit "$CLIENT_DIR/api.py"

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
