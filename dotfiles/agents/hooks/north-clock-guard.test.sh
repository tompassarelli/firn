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

CANON_ROOT="$SCRATCH/code"
CANON_CLIENT="$CANON_ROOT/client/msa"
CANON_NONCLIENT="$CANON_ROOT/nixos-config"
CANON_LINK="$CANON_ROOT/msa-link"
mkdir -p "$CANON_CLIENT" "$CANON_NONCLIENT"
ln -s "$CANON_CLIENT" "$CANON_LINK"
MANY_NONCLIENT="$SCRATCH/many-nonclient"
mkdir -p "$MANY_NONCLIENT"
for ((index = 0; index < 140; index++)); do
  : >"$MANY_NONCLIENT/module-$index.bnix"
done
HOSTILE_COMMA_BRACE="$MANY_NONCLIENT/{"
for ((index = 1; index <= 140; index++)); do
  [ "$index" = 1 ] || HOSTILE_COMMA_BRACE+=","
  HOSTILE_COMMA_BRACE+="module-$index"
done
HOSTILE_COMMA_BRACE+="}.bnix"
CARTESIAN_NONCLIENT="$SCRATCH/cartesian-nonclient"
for ((directory = 1; directory <= 10; directory++)); do
  mkdir -p "$CARTESIAN_NONCLIENT/$directory"
  for ((file = 1; file <= 20; file++)); do
    : >"$CARTESIAN_NONCLIENT/$directory/module-$file.bnix"
  done
done
CLIENT_DIR="$CANON_CLIENT"
NONCLIENT="$CANON_NONCLIENT"
QUOTED_NONCLIENT="$CANON_ROOT/non client"
mkdir -p "$QUOTED_NONCLIENT"
git -C "$CLIENT_DIR" init -q -b msa-242-work
git -C "$CLIENT_DIR" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty --no-verify -qm init

# ---- fixtures: minimal fact logs in the facts.log line shape --------------
# An OPEN human client session for msa. Ticket traceability is a separate thread.
cat >"$SCRATCH/open-msa.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-1", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-1", :p "owner", :r "msa", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-1", :p "clocked_by", :r "user", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-1", :p "rate", :r "175", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-1", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

# The human stays clocked into msa while the branch moves to another msa ticket.
cat >"$SCRATCH/open-msa-wrong-ticket.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa-current", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa-current", :p "linear", :r "MSA-242", :by "coord"}
{:tx 3, :op "assert", :l "@thread-msa-other", :p "owner", :r "msa", :by "coord"}
{:tx 4, :op "assert", :l "@thread-msa-other", :p "linear", :r "MSA-999", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa-current", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 91, :op "assert", :l "@thread-msa-other", :p "title", :r "MSA-999 other", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-msa", :p "kind", :r "client_session", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-msa", :p "owner", :r "msa", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-msa", :p "clocked_by", :r "user", :by "coord"}
{:tx 8, :op "assert", :l "@client-session-msa", :p "rate", :r "175", :by "coord"}
{:tx 9, :op "assert", :l "@client-session-msa", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

cat >"$SCRATCH/duplicate-ticket-threads.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa-a", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa-a", :p "linear", :r "MSA-242", :by "coord"}
{:tx 3, :op "assert", :l "@thread-msa-b", :p "owner", :r "msa", :by "coord"}
{:tx 4, :op "assert", :l "@thread-msa-b", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa-a", :p "title", :r "first MSA-242", :by "coord"}
{:tx 91, :op "assert", :l "@thread-msa-b", :p "title", :r "second MSA-242", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-msa", :p "kind", :r "client_session", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-msa", :p "owner", :r "msa", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-msa", :p "clocked_by", :r "user", :by "coord"}
{:tx 8, :op "assert", :l "@client-session-msa", :p "rate", :r "175", :by "coord"}
{:tx 9, :op "assert", :l "@client-session-msa", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

# An OPEN human session owned by another client (wrong owner for an msa edit).
cat >"$SCRATCH/open-personal.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-acme", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-acme", :p "owner", :r "acme", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-acme", :p "clocked_by", :r "user", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-acme", :p "rate", :r "200", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-acme", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

# No open session: the human msa session was started then closed.
cat >"$SCRATCH/closed.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-1", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-1", :p "owner", :r "msa", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-1", :p "clocked_by", :r "user", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-1", :p "rate", :r "175", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-1", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
{:tx 8, :op "assert", :l "@client-session-1", :p "end_time", :r "2026-07-15T11:00:00", :by "coord"}
EOF

# Multiple open human client sessions are ambiguous and fail closed.
cat >"$SCRATCH/two-open.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-acme", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-acme", :p "owner", :r "acme", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-acme", :p "clocked_by", :r "user", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-acme", :p "rate", :r "200", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-acme", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
{:tx 8, :op "assert", :l "@client-session-msa", :p "kind", :r "client_session", :by "coord"}
{:tx 9, :op "assert", :l "@client-session-msa", :p "owner", :r "msa", :by "coord"}
{:tx 10, :op "assert", :l "@client-session-msa", :p "clocked_by", :r "user", :by "coord"}
{:tx 11, :op "assert", :l "@client-session-msa", :p "rate", :r "175", :by "coord"}
{:tx 12, :op "assert", :l "@client-session-msa", :p "start_time", :r "2026-07-15T10:05:00", :by "coord"}
EOF

cat >"$SCRATCH/agent-run-only.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@run-1", :p "kind", :r "run", :by "coord"}
{:tx 4, :op "assert", :l "@run-1", :p "owner", :r "msa", :by "coord"}
{:tx 5, :op "assert", :l "@run-1", :p "clocked_by", :r "agent", :by "coord"}
{:tx 6, :op "assert", :l "@run-1", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

cat >"$SCRATCH/legacy-session-only.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@legacy-session", :p "owner", :r "msa", :by "coord"}
{:tx 4, :op "assert", :l "@legacy-session", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

cat >"$SCRATCH/non-user-client-session.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-agent", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-agent", :p "owner", :r "msa", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-agent", :p "clocked_by", :r "agent", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-agent", :p "rate", :r "175", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-agent", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

cat >"$SCRATCH/missing-ticket-trace.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-other", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-other", :p "linear", :r "MSA-999", :by "coord"}
{:tx 90, :op "assert", :l "@thread-other", :p "title", :r "MSA-999 other", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-msa", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-msa", :p "owner", :r "msa", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-msa", :p "clocked_by", :r "user", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-msa", :p "rate", :r "175", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-msa", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

cat >"$SCRATCH/titleless-ticket-trace.log" <<'EOF'
{:tx 1, :op "assert", :l "@malformed-ticket-subject", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@malformed-ticket-subject", :p "linear", :r "MSA-242", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-msa", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-msa", :p "owner", :r "msa", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-msa", :p "clocked_by", :r "user", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-msa", :p "rate", :r "175", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-msa", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

cat >"$SCRATCH/whitespace-title-ticket-trace.log" <<'EOF'
{:tx 1, :op "assert", :l "@malformed-ticket-subject", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@malformed-ticket-subject", :p "linear", :r "MSA-242", :by "coord"}
{:tx 3, :op "assert", :l "@malformed-ticket-subject", :p "title", :r "   ", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-msa", :p "kind", :r "client_session", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-msa", :p "owner", :r "msa", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-msa", :p "clocked_by", :r "user", :by "coord"}
{:tx 7, :op "assert", :l "@client-session-msa", :p "rate", :r "175", :by "coord"}
{:tx 8, :op "assert", :l "@client-session-msa", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

cat >"$SCRATCH/incomplete-client-session.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa", :by "coord"}
{:tx 2, :op "assert", :l "@thread-msa", :p "linear", :r "MSA-242", :by "coord"}
{:tx 90, :op "assert", :l "@thread-msa", :p "title", :r "MSA-242 digest", :by "coord"}
{:tx 3, :op "assert", :l "@client-session-msa", :p "kind", :r "client_session", :by "coord"}
{:tx 4, :op "assert", :l "@client-session-msa", :p "owner", :r "msa", :by "coord"}
{:tx 5, :op "assert", :l "@client-session-msa", :p "clocked_by", :r "user", :by "coord"}
{:tx 6, :op "assert", :l "@client-session-msa", :p "start_time", :r "2026-07-15T10:00:00", :by "coord"}
EOF

# Corpus uncertainty fixtures.
printf '%s\n' 'not-a-fram-fact' >"$SCRATCH/garbled.log"
cat >"$SCRATCH/malformed-relevant.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner"}
EOF
cat >"$SCRATCH/duplicate-tx.log" <<'EOF'
{:tx 1, :op "assert", :l "@thread-msa", :p "owner", :r "msa"}
{:tx 1, :op "assert", :l "@client-session-1", :p "kind", :r "client_session"}
EOF
cp "$SCRATCH/open-msa.log" "$SCRATCH/unreadable.log"
chmod 000 "$SCRATCH/unreadable.log"
mkdir -p "$SCRATCH/partial-split"
cp "$SCRATCH/open-msa.log" "$SCRATCH/partial-split/coordination.log"

pass=0 fail=0
CLOCK_ALLOW='{ "northClockGuard": "allow" }'
NOT_APPLICABLE='{ "northClockGuard": "not-applicable" }'
UNAVAILABLE_REASON='"permissionDecisionReason":"billable_clock_guard_unavailable"'

# emit_json TOOL FP_OR_CMD CWD  — build a PreToolUse payload for a tool.
emit_json() {
  local tool="$1" arg="$2" cwd="${3:-}"
  if [ "$tool" = Bash ]; then
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$arg" "$cwd"
  else
    python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2]}}))' "$tool" "$arg"
  fi
}

emit_patch_json() {
  local tool="$1" patch="$2" cwd="$3"
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]},"cwd":sys.argv[3]}))' \
    "$tool" "$patch" "$cwd"
}

emit_workdir_json() {
  local command="$1" cwd="$2" workdir="$3"
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1],"workdir":sys.argv[3]},"cwd":sys.argv[2]}))' \
    "$command" "$cwd" "$workdir"
}

# run EXPECT DESC LOG TOOL ARG [CWD] — attestation mode expectations:
#   clock       -> exactly one root matching-clock attestation
#   na          -> exactly one root not-applicable attestation
#   deny        -> precise no-clock deny (not infrastructure-unavailable)
#   mismatch    -> precise wrong-owner-clock deny
#   unavailable -> stable fail-closed infrastructure reason
check_output() {
  local expect="$1" desc="$2" out="$3"
  local denied=0 mism=0 unavailable=0 ticket=0 trace=0
  case "$out" in
    *'"permissionDecision":"deny"'*|*'"permissionDecision": "deny"'*) denied=1 ;;
  esac
  case "$out" in *'WRONG client clock'*) mism=1 ;; esac
  case "$out" in *"$UNAVAILABLE_REASON"*) unavailable=1 ;; esac
  case "$out" in *'branch ticket is missing or ambiguous'*) ticket=1 ;; esac
  case "$out" in *'exact North traceability thread'*) trace=1 ;; esac
  local ok=0
  case "$expect" in
    clock)    [ "$out" = "$CLOCK_ALLOW" ] && ok=1 ;;
    na)       [ "$out" = "$NOT_APPLICABLE" ] && ok=1 ;;
    deny)     [ "$denied" = 1 ] && [ "$unavailable" = 0 ] &&
              [[ "$out" == *'no north clock running'* ]] && ok=1 ;;
    mismatch) [ "$denied" = 1 ] && [ "$mism" = 1 ] && ok=1 ;;
    ticket)   [ "$denied" = 1 ] && [ "$ticket" = 1 ] && ok=1 ;;
    trace)    [ "$denied" = 1 ] && [ "$trace" = 1 ] && ok=1 ;;
    unavailable) [ "$denied" = 1 ] && [ "$unavailable" = 1 ] && ok=1 ;;
    silent) [ -z "$out" ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %-11s  %s\n' "$expect" "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-11s  %s\n      denied=%s mism=%s ticket=%s trace=%s unavailable=%s out=%s\n' \
      "$expect" "$desc" "$denied" "$mism" "$ticket" "$trace" "$unavailable" "$out"
  fi
}

run() {
  local expect="$1" desc="$2" log="$3" tool="$4" arg="$5" cwd="${6:-}"
  local json out
  json="$(emit_json "$tool" "$arg" "$cwd")"
  out="$(printf '%s' "$json" | env -u AGENT_NO_AUTHORING_HOOKS \
    -u CLAUDE_NO_AUTHORING_HOOKS -u FRAM_TELEMETRY_LOG \
    NORTH_CLOCK_GUARD_ATTEST=1 \
    FRAM_LOG="$SCRATCH/$log" \
    AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
    "$HOOK" 2>/dev/null)"
  check_output "$expect" "$desc" "$out"
}

run_payload() {
  local mode="$1" expect="$2" desc="$3" log="$4" json="$5"
  local out
  if [ "$mode" = attest ]; then
    out="$(printf '%s' "$json" | env -u AGENT_NO_AUTHORING_HOOKS \
      -u CLAUDE_NO_AUTHORING_HOOKS -u FRAM_TELEMETRY_LOG \
      NORTH_CLOCK_GUARD_ATTEST=1 FRAM_LOG="$SCRATCH/$log" \
      AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
      "$HOOK" 2>/dev/null)"
  else
    out="$(printf '%s' "$json" | env -u AGENT_NO_AUTHORING_HOOKS \
      -u CLAUDE_NO_AUTHORING_HOOKS -u NORTH_CLOCK_GUARD_ATTEST \
      -u FRAM_TELEMETRY_LOG FRAM_LOG="$SCRATCH/$log" \
      AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
      "$HOOK" 2>/dev/null)"
  fi
  check_output "$expect" "$desc" "$out"
}

run_with_home() {
  local expect="$1" desc="$2" log="$3" command="$4" cwd="$5" home="$6"
  local json out
  json="$(emit_json Bash "$command" "$cwd")"
  out="$(printf '%s' "$json" | env -u AGENT_NO_AUTHORING_HOOKS \
    -u CLAUDE_NO_AUTHORING_HOOKS -u FRAM_TELEMETRY_LOG \
    HOME="$home" NORTH_CLOCK_GUARD_ATTEST=1 \
    FRAM_LOG="$SCRATCH/$log" \
    AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
    "$HOOK" 2>/dev/null)"
  check_output "$expect" "$desc" "$out"
}

echo "== deliverable cases (a)-(g) =="
run deny     '(a) Edit client path, no open session'                closed.log        Edit "$CLIENT_DIR/api.py"
run clock    '(b) Edit client path, open session owner=msa'         open-msa.log      Edit "$CLIENT_DIR/api.py"
run mismatch '(c) Edit client path, open session owner=personal'    open-personal.log Edit "$CLIENT_DIR/api.py"
run deny     '(d) Bash sed -i on client path, no clock'             closed.log        Bash "sed -i s/a/b/ $CLIENT_DIR/api.py"
run deny     '(e) ambient Git read may execute configured helpers' closed.log        Bash "git log --oneline -5" "$CLIENT_DIR"
run na       '(f) Edit outside client'                              closed.log        Edit "$NONCLIENT/flake.nix"
run unavailable '(g) multiple human client sessions are ambiguous' two-open.log      Edit "$CLIENT_DIR/api.py"
run clock    '(h) same-client ticket switch keeps the human clock'  open-msa-wrong-ticket.log Edit "$CLIENT_DIR/api.py"
run unavailable '(i) duplicate ticket-thread identity cannot authorize' duplicate-ticket-threads.log Edit "$CLIENT_DIR/api.py"
run deny     '(j) agent run telemetry cannot authorize billing'     agent-run-only.log Edit "$CLIENT_DIR/api.py"
run deny     '(k) legacy session shape cannot authorize billing'    legacy-session-only.log Edit "$CLIENT_DIR/api.py"
run deny     '(l) non-user client_session cannot authorize billing' non-user-client-session.log Edit "$CLIENT_DIR/api.py"
run trace    '(m) matching human clock cannot replace ticket trace' missing-ticket-trace.log Edit "$CLIENT_DIR/api.py"
run trace    '(n) owner+Linear without title is not a North thread' titleless-ticket-trace.log Edit "$CLIENT_DIR/api.py"
run trace    '(o) whitespace title is not a North thread' whitespace-title-ticket-trace.log Edit "$CLIENT_DIR/api.py"
run unavailable '(p) incomplete human billing row fails closed' incomplete-client-session.log Edit "$CLIENT_DIR/api.py"

echo "== output protocol: native silence vs opt-in machine attestation =="
open_edit_json="$(emit_json Edit "$CLIENT_DIR/api.py")"
outside_edit_json="$(emit_json Edit "$NONCLIENT/flake.nix")"
closed_edit_json="$(emit_json Edit "$CLIENT_DIR/api.py")"
run_payload native silent 'native matching clock is protocol-valid silent allow' open-msa.log "$open_edit_json"
run_payload native silent 'native nonbillable call is protocol-valid silent allow' closed.log "$outside_edit_json"
run_payload native deny   'native honest no-clock denial remains protocol JSON' closed.log "$closed_edit_json"
run_payload attest clock  'attestation mode proves matching owner clock exactly once' open-msa.log "$open_edit_json"
run_payload attest na     'attestation mode proves deterministic non-applicability' closed.log "$outside_edit_json"

echo "== branch ticket identity is exact and unambiguous =="
git -C "$CLIENT_DIR" switch -q -c work-without-ticket
run ticket 'client worktree without CLIENT-NNN branch ticket is rejected' \
  open-msa.log Edit "$CLIENT_DIR/api.py"
git -C "$CLIENT_DIR" switch -q -c msa-242-and-msa-243
run ticket 'branch containing two ticket identities is rejected as ambiguous' \
  open-msa.log Edit "$CLIENT_DIR/api.py"
git -C "$CLIENT_DIR" switch -q msa-242-work
FAKE_GIT_REPO="$SCRATCH/fake-git-repo"
mkdir -p "$FAKE_GIT_REPO"
git -C "$FAKE_GIT_REPO" init -q -b msa-999-work
git -C "$FAKE_GIT_REPO" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty --no-verify -qm init
printf '%s\n' '[core]' '  fsmonitor = /tmp/ambient-helper' \
  >"$SCRATCH/ambient-git-config"
GIT_DIR="$FAKE_GIT_REPO/.git" \
GIT_WORK_TREE="$FAKE_GIT_REPO" \
GIT_CONFIG_GLOBAL="$SCRATCH/ambient-git-config" \
GIT_CONFIG_SYSTEM="$SCRATCH/ambient-git-config" \
GIT_CEILING_DIRECTORIES="/" \
GIT_PAGER="/tmp/ambient-helper" \
GIT_EXTERNAL_DIFF="/tmp/ambient-helper" \
  run clock 'trusted branch proof ignores every inherited Git redirect/helper' \
    open-msa.log Edit "$CLIENT_DIR/api.py"

echo "== exact Codex 0.144.4 canonical hook envelopes =="
# Codex canonicalizes apply_patch to tool_name=apply_patch and places the raw
# patch in tool_input.command. Unified exec canonicalizes to Bash with
# tool_input.command and the turn cwd at the common root.
client_patch="$(printf '%s\n' '*** Begin Patch' "*** Update File: $CLIENT_DIR/api.py" '@@' '-old' '+new' '*** End Patch')"
nonclient_patch="$(printf '%s\n' '*** Begin Patch' "*** Update File: $NONCLIENT/flake.nix" '@@' '-old' '+new' '*** End Patch')"
decoy_patch="$(printf '%s\n' '*** Begin Patch' "*** Update File: $NONCLIENT/flake.nix" '@@' '-old' '+# /code/client/msa/mentioned only in patch content' '*** End Patch')"
multi_nonclient_patch="$(printf '%s\n' '*** Begin Patch' \
  "*** Update File: $NONCLIENT/flake.nix" '@@' '-a' '+b' \
  "*** Update File: $NONCLIENT/README.md" '@@' '-c' '+d' '*** End Patch')"
mixed_clients_patch="$(printf '%s\n' '*** Begin Patch' \
  "*** Update File: $HOME/code/client/msa/a" '@@' '-a' '+b' \
  "*** Update File: $HOME/code/client/acme/b" '@@' '-c' '+d' '*** End Patch')"
run_payload attest clock 'Codex apply_patch client target + matching clock' open-msa.log \
  "$(emit_patch_json apply_patch "$client_patch" "$NONCLIENT")"
run_payload attest na 'Codex apply_patch nonclient target' closed.log \
  "$(emit_patch_json apply_patch "$nonclient_patch" "$NONCLIENT")"
run_payload attest na 'patch content cannot impersonate a client target' closed.log \
  "$(emit_patch_json apply_patch "$decoy_patch" "$NONCLIENT")"
run_payload attest na 'multi-file nonclient apply_patch remains nonbillable' closed.log \
  "$(emit_patch_json apply_patch "$multi_nonclient_patch" "$NONCLIENT")"
run_payload attest unavailable 'one patch cannot borrow one client clock for another client' open-msa.log \
  "$(emit_patch_json apply_patch "$mixed_clients_patch" "$NONCLIENT")"
run_payload attest unavailable 'apply_patch without target headers is malformed' closed.log \
  "$(emit_patch_json apply_patch '*** Begin Patch
*** End Patch' "$NONCLIENT")"
run_payload attest deny 'Codex unified exec canonical Bash envelope remains clocked for Git' closed.log \
  "$(emit_json Bash 'git status' "$CLIENT_DIR")"

echo "== canonical path identity: traversal and symlinks cannot hide client work =="
run deny 'Edit ../ traversal resolves into client tree' closed.log Edit \
  "$CANON_NONCLIENT/../client/msa/new.py"
run deny 'Edit through symlink resolves into client tree' closed.log Edit \
  "$CANON_LINK/new.py"
run deny 'relative shell traversal resolves into client tree' closed.log Bash \
  "rm -f ../client/msa/new.py" "$CANON_NONCLIENT"
run deny 'shell target through symlink resolves into client tree' closed.log Bash \
  "rm -f $CANON_LINK/new.py" "$CANON_NONCLIENT"
traversal_patch="$(printf '%s\n' '*** Begin Patch' \
  '*** Add File: ../client/msa/new.py' '+new' '*** End Patch')"
run_payload attest deny 'apply_patch traversal resolves into client tree' closed.log \
  "$(emit_patch_json apply_patch "$traversal_patch" "$CANON_NONCLIENT")"

echo "== bash mutation heuristic: mutations gated =="
run deny  'redirect > into client file, no clock'   closed.log Bash "echo x > $CLIENT_DIR/out.txt"
run deny  'redirect >> append, no clock'            closed.log Bash "printf y >> $CLIENT_DIR/out.txt"
run deny  'redirect <> opens client file read-write' closed.log Bash "cat <> $CLIENT_DIR/out.txt"
run deny  'redirect >| clobbers despite noclobber'   closed.log Bash "cat >| $CLIENT_DIR/out.txt"
run deny  'redirect &> writes both streams to client file' closed.log Bash "cat missing &> $CLIENT_DIR/out.txt"
run deny  'git commit in client cwd, no clock'      closed.log Bash "git commit -m wip" "$CLIENT_DIR"
run deny  'rm in client cwd, no clock'              closed.log Bash "rm -f build.o" "$CLIENT_DIR"
run deny  'cp into client path, no clock'           closed.log Bash "cp /tmp/x $CLIENT_DIR/x"
run deny  'mv in client cwd, no clock'              closed.log Bash "mv a b" "$CLIENT_DIR"
run deny  'tee client file, no clock'               closed.log Bash "echo x | tee $CLIENT_DIR/f"
run deny  'npm install in client cwd, no clock'     closed.log Bash "npm install" "$CLIENT_DIR"
run clock 'git commit in client cwd, clock owner=msa'  open-msa.log Bash "git commit -m done" "$CLIENT_DIR"
run deny  'git -C explicit client commit, no clock' closed.log Bash "git -C $CLIENT_DIR commit -m done" "$NONCLIENT"
run clock 'git -C explicit client commit, matching clock' open-msa.log Bash "git -C $CLIENT_DIR commit -m done" "$NONCLIENT"

echo "== generic writer attribution: syntax does not define the security boundary =="
run deny 'arbitrary interpreter with literal client path is attributed' \
  closed.log Bash "python3 -c 'open(\"$CLIENT_DIR/from-python\", \"w\").close()'" "$NONCLIENT"
run deny 'interpreter assignment text cannot disguise a literal client path' \
  closed.log Bash "python3 -c 'TARGET=\"$CLIENT_DIR/from-python-assignment\"; open(TARGET, \"w\").close()'" "$NONCLIENT"
run na 'URL text containing a client-shaped suffix is not a local path' \
  closed.log Bash "python3 -c 'print(\"https://example.invalid/code/client/msa/data\")'" "$NONCLIENT"
run deny 'git clone destination under a client is attributed' \
  closed.log Bash "git clone https://example.invalid/repo $CLIENT_DIR/clone" "$NONCLIENT"
run deny 'git init destination under a client is attributed' \
  closed.log Bash "git init $CLIENT_DIR/init" "$NONCLIENT"
run deny 'git worktree destination under a client is attributed' \
  closed.log Bash "git worktree add $CLIENT_DIR/worktree topic" "$NONCLIENT"

echo "== bounded shell path expansion cannot hide client attribution =="
run_with_home deny 'literal $HOME client target is resolved' closed.log \
  'rm "$HOME/code/client/msa/from-home"' "$NONCLIENT" "$SCRATCH"
run_with_home deny 'literal ${HOME} client target is resolved' closed.log \
  'rm "${HOME}/code/client/msa/from-braced-home"' "$NONCLIENT" "$SCRATCH"
run_with_home deny 'assigned target is resolved before the mutator' closed.log \
  'TARGET="$HOME/code/client/msa/from-assignment"; rm "$TARGET"' \
  "$NONCLIENT" "$SCRATCH"
run_with_home deny 'leading environment assignment consumed by code is attributed' \
  closed.log \
  'TARGET="$HOME/code/client/msa/from-env" python3 -c '"'"'open(__import__("os").environ["TARGET"], "w").close()'"'" \
  "$NONCLIENT" "$SCRATCH"
run_with_home deny 'tilde expansion inside an assigned target is resolved' \
  closed.log 'TARGET=~/code/client/msa/from-tilde; rm "$TARGET"' \
  "$NONCLIENT" "$SCRATCH"
run_with_home na 'assignment-only command does not write a client path' \
  closed.log 'TARGET="$HOME/code/client/msa/data-only"' \
  "$NONCLIENT" "$SCRATCH"
run unavailable 'unsupported parameter expansion in a mutator fails closed' \
  closed.log Bash 'rm "${TARGET:-/home/tom/code/client/msa/fallback}"' "$NONCLIENT"
run deny 'client glob remains attributed when it has no matches' \
  closed.log Bash "rm $CLIENT_DIR/*.never-matches" "$NONCLIENT"
run deny 'bounded brace expansion within one client is attributed' \
  closed.log Bash "rm $CLIENT_DIR/{one,two}" "$NONCLIENT"
run unavailable 'brace expansion spanning clients cannot borrow one clock' \
  closed.log Bash "rm $CANON_ROOT/client/{msa,acme}/out" "$NONCLIENT"
run unavailable 'wildcard client identity fails closed' \
  closed.log Bash "rm $CANON_ROOT/client/*/out" "$NONCLIENT"

echo "== exact trusted mktemp assignment can name only a proved nonclient destination =="
printf -v gaffer_mktemp_pipeline '%s\n' \
  'set -euo pipefail' \
  'tmp="$(mktemp -d)"' \
  'trap '\''rm -rf "$tmp"'\'' EXIT' \
  "cp -a $NONCLIENT/. \"\$tmp/\"" \
  "perl -0pi -e 's/old/new/' \"\$tmp/catalog.json\"" \
  "if node \"\$tmp/validate.mjs\" >\"\$tmp/stdout\" 2>\"\$tmp/stderr\"; then" \
  '  exit 1' \
  'fi' \
  "rg -F validation-error \"\$tmp/stderr\""
TMPDIR='' run na 'exact Gaffer validation-shaped mktemp pipeline is nonclient' \
  closed.log Bash "$gaffer_mktemp_pipeline" "$NONCLIENT"
TMPDIR='' run na 'unquoted exact mktemp assignment feeds a nonclient cp' \
  closed.log Bash \
  "tmp=\$(mktemp -d); cp -a $NONCLIENT/. \"\$tmp/\"" \
  "$NONCLIENT"
TMPDIR='' run na 'proved mktemp value propagates through a simple assignment' \
  closed.log Bash \
  "tmp=\"\$(mktemp -d)\"; dest=\"\$tmp\"; cp -a $NONCLIENT/. \"\$dest/\"" \
  "$NONCLIENT"
mkdir -p "$SCRATCH/safe-tmp-root"
TMPDIR="$SCRATCH/safe-tmp-root" \
  run na 'explicit canonical nonclient TMPDIR remains supported' \
    closed.log Bash \
    "tmp=\"\$(mktemp -d)\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
    "$NONCLIENT"
TMPDIR="$CLIENT_DIR" \
  run unavailable 'client-scoped TMPDIR cannot bless a dynamic destination' \
    closed.log Bash \
    "tmp=\"\$(mktemp -d)\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
    "$NONCLIENT"
TMPDIR="$CANON_LINK" \
  run unavailable 'symlinked client TMPDIR cannot bless a destination' \
    closed.log Bash \
    "tmp=\"\$(mktemp -d)\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
    "$NONCLIENT"
TMPDIR='' run unavailable 'unknown command substitution remains ambiguous' \
  closed.log Bash \
  "tmp=\"\$(printf /tmp/dynamic)\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
  "$NONCLIENT"
TMPDIR='' run unavailable 'mktemp template override is outside the exact proof' \
  closed.log Bash \
  "tmp=\"\$(mktemp -d --tmpdir=$CLIENT_DIR)\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
  "$NONCLIENT"
TMPDIR='' run deny 'later client reassignment supersedes the proved temp value' \
  closed.log Bash \
  "tmp=\"\$(mktemp -d)\"; tmp=\"$CLIENT_DIR\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
  "$NONCLIENT"
TMPDIR='' run deny 'later symlinked-client reassignment remains attributed' \
  closed.log Bash \
  "tmp=\"\$(mktemp -d)\"; tmp=\"$CANON_LINK\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
  "$NONCLIENT"
TMPDIR='' run deny 'compound command cannot hide a later literal client write' \
  closed.log Bash \
  "tmp=\"\$(mktemp -d)\"; cp -a $NONCLIENT/. \"\$tmp/\"; cp -a $NONCLIENT/. $CLIENT_DIR/" \
  "$NONCLIENT"
TMPDIR='' run deny 'EXIT trap with a client operand remains attributed' \
  closed.log Bash \
  "tmp=\"\$(mktemp -d)\"; trap 'cp -a $NONCLIENT/. $CLIENT_DIR/' EXIT; cp -a $NONCLIENT/. \"\$tmp/\"" \
  "$NONCLIENT"
shadow_mktemp_bin="$SCRATCH/shadow-mktemp-bin"
mkdir -p "$shadow_mktemp_bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf /tmp/forged' \
  >"$shadow_mktemp_bin/mktemp"
chmod +x "$shadow_mktemp_bin/mktemp"
PATH="$shadow_mktemp_bin:$PATH" TMPDIR='' \
  run unavailable 'PATH-shadowed mktemp cannot forge a nonclient proof' \
    closed.log Bash \
    "tmp=\"\$(mktemp -d)\"; cp -a $NONCLIENT/. \"\$tmp/\"" \
    "$NONCLIENT"

echo "== write/exec-capable read-command options are never blessed =="
run deny 'find -fprint writes an output file' closed.log Bash \
  "find . -fprint generated.txt" "$CLIENT_DIR"
run deny 'sed w command writes an output file' closed.log Bash \
  "sed -n 'w generated.txt' input" "$CLIENT_DIR"
run deny 'sed e command executes a helper' closed.log Bash \
  "sed -n '1e touch generated.txt' input" "$CLIENT_DIR"
run deny 'sed later -e cannot append a write script' closed.log Bash \
  "sed -n '1p' input -e 'w generated.txt'" "$CLIENT_DIR"
run deny 'sed later -f cannot load an unproved script' closed.log Bash \
  "sed -n '1p' input -f commands.sed" "$CLIENT_DIR"
run deny 'sort -o writes an output file' closed.log Bash \
  "sort -o generated.txt input" "$CLIENT_DIR"
run deny 'git diff --output writes an output file' closed.log Bash \
  "git diff --output=generated.patch" "$CLIENT_DIR"
run deny 'git diff --ext-diff may execute a helper' closed.log Bash \
  "git diff --ext-diff" "$CLIENT_DIR"
run deny 'assignment-driven git diff helper is not read-only' closed.log Bash \
  "GIT_EXTERNAL_DIFF='touch generated.txt' git diff" "$CLIENT_DIR"
run deny 'curl --config may select output/upload behavior' closed.log Bash \
  "curl --config request.cfg" "$CLIENT_DIR"
run deny 'curl compact -d sends mutation-capable data' closed.log Bash \
  "curl -dfoo https://example.invalid" "$CLIENT_DIR"
run deny 'curl compact -F sends a mutation-capable form' closed.log Bash \
  "curl -Ffoo=bar https://example.invalid" "$CLIENT_DIR"
run deny 'curl compact -XPOST changes request method' closed.log Bash \
  "curl -XPOST https://example.invalid" "$CLIENT_DIR"
run deny 'curl compact -o writes an output file' closed.log Bash \
  "curl -ogenerated.txt https://example.invalid" "$CLIENT_DIR"
run deny 'curl compact -T uploads a file' closed.log Bash \
  "curl -Tinput https://example.invalid" "$CLIENT_DIR"
run deny 'curl --json sends mutation-capable data' closed.log Bash \
  "curl --json '{}' https://example.invalid" "$CLIENT_DIR"
run deny 'curl --etag-save persists state' closed.log Bash \
  "curl --etag-save etag.txt https://example.invalid" "$CLIENT_DIR"
run deny 'curl --hsts persists state' closed.log Bash \
  "curl --hsts hsts.txt https://example.invalid" "$CLIENT_DIR"
run deny 'curl --alt-svc persists state' closed.log Bash \
  "curl --alt-svc altsvc.txt https://example.invalid" "$CLIENT_DIR"
run deny 'curl --stderr writes a log file' closed.log Bash \
  "curl --stderr curl.log https://example.invalid" "$CLIENT_DIR"
run deny 'rg --pre executes a helper' closed.log Bash \
  "rg --pre 'touch generated.txt' needle ." "$CLIENT_DIR"
RIPGREP_CONFIG_PATH="$SCRATCH/ripgrep.conf" \
  run deny 'ambient ripgrep config prevents a read-only proof' closed.log Bash \
    "rg needle ." "$CLIENT_DIR"

echo "== unknown client-attributed Bash fails toward clocked, never silent nonbillable =="
run deny  'unknown Python command in client cwd requires clock' closed.log Bash "python3 -c 'print(1)'" "$CLIENT_DIR"
run clock 'unknown Python command is allowed only with matching clock' open-msa.log Bash "python3 -c 'print(1)'" "$CLIENT_DIR"
run deny  'git tag with an argument is not misclassified as read-only' closed.log Bash "git tag release-test" "$CLIENT_DIR"
run deny  'command wrapper cannot hide a mutator' closed.log Bash "command rm build.o" "$CLIENT_DIR"

malicious_bash_env="$SCRATCH/malicious-bash-env"
printf '%s\n' 'cat() { touch "$CLIENT_DIR/from-bash-env"; }' >"$malicious_bash_env"
BASH_ENV="$malicious_bash_env" \
  run deny 'ambient BASH_ENV prevents a read-only executable proof' \
    closed.log Bash "cat README.md" "$CLIENT_DIR"
ENV="$malicious_bash_env" \
  run deny 'ambient ENV prevents a provider-shell read-only proof' \
    closed.log Bash "cat README.md" "$CLIENT_DIR"

echo "== North coordination and client-clock recovery cannot deadlock behind this guard =="
run na 'exact north clock in recovery command is exempt' closed.log Bash \
  "north clock in msa" "$CLIENT_DIR"
run na 'exact north clock status control command is exempt' closed.log Bash \
  "north clock status" "$CLIENT_DIR"
run na 'exact north clock out recovery command is exempt' closed.log Bash \
  "north clock out" "$CLIENT_DIR"
run na 'exact tell repairs the observed Linear identity catch-22' closed.log Bash \
  "north tell 019f8081-28d9-7d52-b65f-68aae73446d9 linear MSA-244" "$CLIENT_DIR"
run na 'guard kill-switch command is itself always reachable' closed.log Bash \
  "north config guards off" "$CLIENT_DIR"
run na 'capture can create missing traceability while an edit is denied' closed.log Bash \
  "north capture 'MSA-244 digest delivery' msa" "$CLIENT_DIR"
canonical_north="$(realpath "$(command -v north)")"
run na 'canonical absolute trusted north control remains exempt' closed.log Bash \
  "$canonical_north clock status" "$CLIENT_DIR"
run deny 'path-qualified north impostor cannot claim control exemption' closed.log Bash \
  "/tmp/north anything" "$CLIENT_DIR"
mkdir -p "$SCRATCH/north-link"
ln -s "$canonical_north" "$SCRATCH/north-link/north"
run deny 'path-qualified north symlink cannot claim control exemption' closed.log Bash \
  "$SCRATCH/north-link/north clock status" "$CLIENT_DIR"
run deny 'env wrapper cannot claim north control exemption' closed.log Bash \
  "env north clock status" "$CLIENT_DIR"
run deny 'command wrapper cannot claim north control exemption' closed.log Bash \
  "command north clock status" "$CLIENT_DIR"
NORTH_TEST='1' run deny 'assignment cannot claim north control exemption' \
  closed.log Bash "NORTH_TEST=1 north clock status" "$CLIENT_DIR"
CONTROL='north' run deny 'parameter command cannot claim north control exemption' \
  closed.log Bash "\${CONTROL} clock status" "$CLIENT_DIR"
run deny 'compound north control command is never exempt' closed.log Bash \
  "north clock in msa && true" "$CLIENT_DIR"
run deny 'north output redirected into client code remains a mutation' closed.log Bash \
  "north clock status > $CLIENT_DIR/clock-status" "$CLIENT_DIR"

echo "== bash mutation heuristic: pure reads never deny =="
run deny 'git status in client cwd may execute fsmonitor' closed.log Bash "git status" "$CLIENT_DIR"
run deny 'git diff in client cwd may execute diff/textconv helpers' closed.log Bash "git diff HEAD~1" "$CLIENT_DIR"
run deny 'git -C explicit client status remains clocked' closed.log Bash "git -C $CLIENT_DIR status" "$NONCLIENT"
run na 'grep client file (2>/dev/null stderr)'   closed.log Bash "grep -n foo $CLIENT_DIR/f 2>/dev/null"
run na 'cat client file'                         closed.log Bash "cat $CLIENT_DIR/README.md"
run na 'ls client dir'                           closed.log Bash "ls -la" "$CLIENT_DIR"
run deny 'find stays outside the tiny execution-free grammar' closed.log Bash "find . -name '*.py'" "$CLIENT_DIR"
run deny 'curl without first -q may load write-capable ~/.curlrc' closed.log Bash \
  "curl -s https://api.github.com" "$CLIENT_DIR"
run deny 'curl GET still crosses the tiny execution-free boundary' closed.log Bash "curl -q -s https://api.github.com" "$CLIENT_DIR"
run deny 'curl compact options remain clocked'    closed.log Bash "curl -q -fsSL https://api.github.com" "$CLIENT_DIR"
run deny 'curl HEAD remains clocked'              closed.log Bash "curl -q -sI https://api.github.com" "$CLIENT_DIR"

echo "== command-position anchoring: mutator words in FILENAMES never deny =="
# The confirmed live defect: bare \b verb boundaries matched inside hyphen-/path-
# delimited filename segments, so a pure read from a client cwd got DENIED.
run na 'EXACT REPRO: pwd && ls mutator words only in filenames' closed.log Bash \
  "pwd && ls -la ~/code/north/bin/north-commit-guard ~/code/north/bin/north-install-commit-guard 2>&1" "$CLIENT_DIR"
run na 'ls path with install/rm/cp/dd/ln in NAMES'   closed.log Bash "ls -la any/path/with-install-rm-cp-dd-ln-in-names" "$CLIENT_DIR"
run na 'cat file named my-cp-notes.txt'              closed.log Bash "cat ./my-cp-notes.txt" "$CLIENT_DIR"
run na 'grep -rn pattern . (recursive read)'         closed.log Bash "grep -rn pattern ." "$CLIENT_DIR"
run na 'read a path segment /x/dd/y.txt'             closed.log Bash "cat /x/dd/y.txt" "$CLIENT_DIR"
run na 'filename not-git-commit.md in an ls'         closed.log Bash "ls -la not-git-commit.md" "$CLIENT_DIR"
run deny 'bun test executes arbitrary project code and is billable' closed.log Bash "bun test" "$CLIENT_DIR"

echo "== fd-dups / fd-prefixed stderr redirects never deny =="
run na 'grep with 2>&1 fd-dup'                       closed.log Bash "grep -n foo bar 2>&1" "$CLIENT_DIR"
run na 'command with >&2 fd-dup'                     closed.log Bash "cat f >&2" "$CLIENT_DIR"
run na 'grep with 2>/dev/null fd-prefixed stderr'    closed.log Bash "grep -n foo bar 2>/dev/null" "$CLIENT_DIR"

echo "== command-position anchoring: real mutations STILL deny =="
run deny  'sed -i at command position'                  closed.log Bash "sed -i s/a/b/ file.ts" "$CLIENT_DIR"
run deny  'sudo rm (through wrapper)'                    closed.log Bash "sudo rm x" "$CLIENT_DIR"
run deny  'rm after && separator'                        closed.log Bash "foo && rm x" "$CLIENT_DIR"
run deny  'rm piped after |'                             closed.log Bash "true | rm x" "$CLIENT_DIR"
run deny  'echo redirect > file'                        closed.log Bash "echo hi > file" "$CLIENT_DIR"
run deny  'single ampersand cannot hide an arbitrary background writer' closed.log Bash \
  "cat README & python3 -c 'open(\"out\", \"w\").write(\"x\")'" "$CLIENT_DIR"

shadow_bin="$SCRATCH/shadow-bin"
mkdir -p "$shadow_bin"
real_cat="$(command -v cat)"
cat >"$shadow_bin/cat" <<EOF
#!/usr/bin/env bash
exec "$real_cat" "\$@"
EOF
chmod +x "$shadow_bin/cat"
PATH="$shadow_bin:$PATH" \
  run deny 'PATH-shadowed allowed command is not trusted as read-only' \
    closed.log Bash "cat README.md" "$CLIENT_DIR"

echo "== cwd-escape: cd to an abs non-client dir attributes THERE, not the session cwd =="
run na 'cd nixos-config && git stash pop (2026-07-16 repro)' closed.log Bash "cd $NONCLIENT && git stash -q && git stash pop -q" "$CLIENT_DIR"
run na 'VAR= prefix then cd non-client && git commit'        closed.log Bash "V=1 && cd $NONCLIENT && git commit -m x" "$CLIENT_DIR"
run na 'explicit nonclient cd scopes bounded composite inspection' closed.log Bash \
  "cd \"$NONCLIENT\" && git status && git log --oneline -5 && sed -n '1,80p' README.md && rg -n needle ." \
  "$CLIENT_DIR"
run na 'quoted nonclient path with spaces establishes scope' closed.log Bash \
  "cd \"$QUOTED_NONCLIENT\" && sed -n '1,20p' README.md && rg -n needle ." \
  "$CLIENT_DIR"
for impostor in git sed rg cat; do
  run deny "path-qualified $impostor impostor cannot establish external scope" \
    closed.log Bash "cd \"$NONCLIENT\" && /tmp/$impostor --version" \
    "$CLIENT_DIR"
done
canonical_git="$(realpath "$(command -v git)")"
run na 'exact canonical trusted executable remains bounded' closed.log Bash \
  "cd \"$NONCLIENT\" && $canonical_git status" "$CLIENT_DIR"
canonical_cat="$(realpath "$(command -v cat)")"
mkdir -p "$SCRATCH/path-qualified"
cat_symlink="$SCRATCH/path-qualified/cat"
ln -s "$canonical_cat" "$cat_symlink"
run deny 'path-qualified symlink cannot impersonate trusted command' closed.log Bash \
  "cd \"$NONCLIENT\" && $cat_symlink README.md" "$CLIENT_DIR"
PATH="$shadow_bin:$PATH" run deny \
  'inline env wrapper cannot redirect a trusted bare command' closed.log Bash \
  "cd \"$NONCLIENT\" && env PATH=$shadow_bin cat README.md" "$CLIENT_DIR"
READER='cat' run deny 'parameter-expanded command token is not trusted' \
  closed.log Bash "cd \"$NONCLIENT\" && \${READER} README.md" "$CLIENT_DIR"
run deny 'nonclient cd cannot hide absolute client mutation' closed.log Bash \
  "cd \"$NONCLIENT\" && sed -i s/a/b/ \"$CLIENT_DIR/api.py\"" \
  "$CLIENT_DIR"
run deny 'later client cd invalidates explicit nonclient scope' closed.log Bash \
  "cd \"$NONCLIENT\" && git status && cd \"$CLIENT_DIR\" && git commit -m x" \
  "$CLIENT_DIR"
run deny 'path-qualified cd impostor cannot establish external scope' closed.log Bash \
  "/tmp/cd \"$NONCLIENT\" && git status" "$CLIENT_DIR"
run deny 'arbitrary shell is not broadly blessed by nonclient cd' closed.log Bash \
  "cd \"$NONCLIENT\" && python3 -c 'print(1)'" "$CLIENT_DIR"
run deny 'arbitrary Git helper is not broadly blessed by nonclient cd' closed.log Bash \
  "cd \"$NONCLIENT\" && git difftool" "$CLIENT_DIR"
run deny 'later sed program option is not blessed by nonclient cd' closed.log Bash \
  "cd \"$NONCLIENT\" && sed -n '1,20p' README.md -e '1w $CLIENT_DIR/generated.txt'" \
  "$CLIENT_DIR"
run deny 'rg preprocessor is not blessed by nonclient cd' closed.log Bash \
  "cd \"$NONCLIENT\" && rg --pre 'touch generated.txt' needle ." \
  "$CLIENT_DIR"
run na 'explicit git -C nonclient scope ignores inherited client cwd' \
  closed.log Bash "git -C $NONCLIENT status" "$CLIENT_DIR"
run na 'explicit git -C nonclient mutation ignores inherited client cwd' \
  closed.log Bash "git -C $NONCLIENT commit -m x" "$CLIENT_DIR"
run_payload attest na 'provider workdir overrides its inherited root client cwd' closed.log \
  "$(emit_workdir_json 'git status' "$CLIENT_DIR" "$NONCLIENT")"
run deny 'explicit git -C config override cannot forge a nonclient proof' \
  closed.log Bash "git -C $NONCLIENT -c test.key=value status" "$CLIENT_DIR"
run deny 'git -c escape remains clocked because config may execute helpers' \
  closed.log Bash "cd $NONCLIENT && git -c test.key=value commit -m x" "$CLIENT_DIR"
if python3 - "$HERE/north-clock-guard.py" "$NONCLIENT" "$CLIENT_DIR" <<'PY'
import runpy
import sys

module = runpy.run_path(sys.argv[1])
if module["git_subcommand"](
    ["git", "-c", "test.key=value", "commit"]
) != "commit":
    raise SystemExit(1)
for command in (
    f"git clone https://example.invalid/repo {sys.argv[3]}/clone",
    f"git init {sys.argv[3]}/init",
    f"git worktree add {sys.argv[3]}/worktree topic",
):
    if "msa" not in module["mutation_paths"](command, sys.argv[2]):
        raise SystemExit(1)
PY
then
  pass=$((pass + 1))
  printf 'PASS  %-11s  %s\n' internal 'Git option and destination mutator branches execute directly'
else
  fail=$((fail + 1))
  printf 'FAIL  %-11s  %s\n' internal 'Git option and destination mutator branches execute directly'
fi
run deny  'cd non-client, client path still in command'         closed.log Bash "cd /tmp && rm -rf $CLIENT_DIR/build" "$CLIENT_DIR"
run deny  'relative cd stays session-attributed'                closed.log Bash "cd sub && git commit -m x" "$CLIENT_DIR"
OLDPWD="$CLIENT_DIR" \
  run deny 'leading cd cannot hide client mutation through OLDPWD' \
    closed.log Bash 'cd /tmp && rm -rf "$OLDPWD"' "$CLIENT_DIR"
outside_link="$SCRATCH/outside-client-link"
ln -s "$CLIENT_DIR/api.py" "$outside_link"
run deny 'leading cd cannot hide a symlinked relative target' \
  closed.log Bash "cd $SCRATCH && touch ${outside_link##*/}" "$CLIENT_DIR"

echo "== fs-mutator with only abs non-client targets acts THERE, not the cwd =="
run na 'rm abs /run path (stop-hook marker shape, 2026-07-16 repro)' closed.log Bash "rm /run/user/1000/north-delegated/session-x" "$CLIENT_DIR"
run na 'mkdir -p abs /tmp path'                             closed.log Bash "mkdir -p /tmp/foo/bar" "$CLIENT_DIR"
run_with_home na 'resolved $HOME nonclient target preserves cwd escape' \
  closed.log 'rm "$HOME/tmp/nonclient-marker"' "$CLIENT_DIR" "$SCRATCH"
run deny  'rm relative target stays cwd-gated'                 closed.log Bash "rm -f build.o" "$CLIENT_DIR"
run deny  'compound rm /tmp then git commit stays gated'       closed.log Bash "rm /tmp/x && git commit -m x" "$CLIENT_DIR"

echo "== sed -i anchoring: an i in a hyphenated ARG (nixos-config) never denies =="
run deny 'sed stays outside the tiny execution-free grammar' closed.log Bash "sed -n '1,80p' $NONCLIENT/dotfiles/agents/hooks/north-clock-guard.sh" "$CLIENT_DIR"
run deny  'sed --in-place still gated'                          closed.log Bash "sed --in-place s/a/b/ f.ts" "$CLIENT_DIR"

echo "== non-client actions remain deterministically not applicable =="
run na 'bare true smoke test cannot fail parser initialization' \
  closed.log Bash "true" "$NONCLIENT"
run na          'Bash mutation outside client'              closed.log      Bash "rm -rf ./build" "$NONCLIENT"
run na 'generic discovery does not enumerate a wholly nonclient large glob' \
  closed.log Bash \
  "rg -n needle $MANY_NONCLIENT/*.bnix" \
  "$NONCLIENT"
run na 'generic discovery does not enumerate a wholly nonclient brace range' \
  closed.log Bash \
  "rg -n needle $MANY_NONCLIENT/{1..140}.bnix" \
  "$NONCLIENT"
run na 'generic discovery does not enumerate a large comma brace' \
  closed.log Bash \
  "rg -n needle $HOSTILE_COMMA_BRACE" \
  "$NONCLIENT"
run na 'generic discovery does not enumerate a nonclient brace-glob product' \
  closed.log Bash \
  "rg -n needle $CARTESIAN_NONCLIENT/{1..10}/*.bnix" \
  "$NONCLIENT"
run unavailable 'known mutator keeps the bounded hostile-glob fail-closed gate' \
  closed.log Bash \
  "rm $MANY_NONCLIENT/*.bnix" \
  "$NONCLIENT"
run unavailable 'known mutator keeps the bounded hostile-brace fail-closed gate' \
  closed.log Bash \
  "rm $MANY_NONCLIENT/{1..140}.bnix" \
  "$NONCLIENT"
run unavailable 'known mutator bounds a large comma brace' \
  closed.log Bash \
  "rm $HOSTILE_COMMA_BRACE" \
  "$NONCLIENT"
run unavailable 'known mutator bounds aggregate brace-glob products' \
  closed.log Bash \
  "rm $CARTESIAN_NONCLIENT/{1..10}/*.bnix" \
  "$NONCLIENT"
run deny 'generic glob below a symlinked client prefix stays attributed' \
  closed.log Bash \
  "python3 -c 'print(1)' $CANON_LINK/*.never-matches" \
  "$NONCLIENT"
run deny 'generic brace below a direct client prefix stays attributed' \
  closed.log Bash \
  "python3 -c 'print(1)' $CLIENT_DIR/{1..140}.never-matches" \
  "$NONCLIENT"
run deny 'generic brace-glob below a symlinked client prefix stays attributed' \
  closed.log Bash \
  "python3 -c 'print(1)' $CANON_LINK/{1..20}/*.never-matches" \
  "$NONCLIENT"
run na 'steering payload may mention a client glob without becoming a path operand' \
  closed.log Bash \
  "north steer session-x 'review $CLIENT_DIR/** after the harness pass'" \
  "$NONCLIENT"
run na 'exact data-only steer is exempt even from a client cwd' \
  closed.log Bash \
  "north steer session-x 'review $CLIENT_DIR/** after the harness pass'" \
  "$CLIENT_DIR"
run deny 'steer output redirection remains a client write' \
  closed.log Bash \
  "north steer session-x status > $CLIENT_DIR/steer-output" \
  "$NONCLIENT"

echo "== malformed envelopes and unavailable/uncertain corpus fail closed =="
run unavailable 'classified client edit + missing corpus' nonexistent.log Edit "$CLIENT_DIR/api.py"
run unavailable 'classified client edit + unreadable corpus' unreadable.log Edit "$CLIENT_DIR/api.py"
run unavailable 'classified client edit + grossly garbled corpus' garbled.log Edit "$CLIENT_DIR/api.py"
run unavailable 'classified client edit + malformed relevant fact' malformed-relevant.log Edit "$CLIENT_DIR/api.py"
run unavailable 'duplicate relevant tx makes fold ordering uncertain' duplicate-tx.log Edit "$CLIENT_DIR/api.py"
run unavailable 'partial canonical split cannot fall back to monolith' partial-split/coordination.log Edit "$CLIENT_DIR/api.py"
run_payload attest unavailable 'malformed JSON envelope' closed.log '{not-json'
run_payload attest unavailable 'duplicate root JSON key cannot replace the tool identity' closed.log \
  '{"tool_name":"Edit","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
run_payload attest unavailable 'duplicate nested JSON key cannot replace a target path' closed.log \
  '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x","file_path":"/tmp/y"}}'
run_payload attest unavailable 'unknown tool cannot forge non-applicability' closed.log \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"cwd":"/tmp"}'
run_payload attest unavailable 'relevant tool without tool_input is malformed' closed.log \
  '{"tool_name":"Edit","cwd":"/tmp"}'

shadow_helper_bin="$SCRATCH/shadow-helper-bin"
mkdir -p "$shadow_helper_bin"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf '\''{ "northClockGuard": "allow" }\n'\''' \
  >"$shadow_helper_bin/python3"
chmod +x "$shadow_helper_bin/python3"
missing_python_json="$(emit_json Edit "$CLIENT_DIR/api.py")"
missing_python_out="$(printf '%s' "$missing_python_json" | env \
  PATH="$shadow_helper_bin" AGENT_NO_AUTHORING_HOOKS=0 \
  NORTH_CLOCK_GUARD_ATTEST=1 FRAM_LOG="$SCRATCH/closed.log" \
  AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
  "$(command -v bash)" "$HOOK" 2>/dev/null)"
check_output deny 'PATH-shadowed python cannot forge a clock allow' "$missing_python_out"

printf '%s\n' '#!/usr/bin/env bash' \
  'case " $* " in *" symbolic-ref "*) printf '\''msa-242-work\n'\'' ;; *) printf '\''/tmp/fake\n'\'' ;; esac' \
  'exit 0' >"$shadow_helper_bin/git"
chmod +x "$shadow_helper_bin/git"
git -C "$CLIENT_DIR" switch -q work-without-ticket
shadow_git_out="$(printf '%s' "$missing_python_json" | env \
  PATH="$shadow_helper_bin:$PATH" AGENT_NO_AUTHORING_HOOKS=0 \
  NORTH_CLOCK_GUARD_ATTEST=1 FRAM_LOG="$SCRATCH/open-msa.log" \
  AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" "$HOOK" 2>/dev/null)"
check_output ticket 'PATH-shadowed git cannot forge branch-ticket admission' "$shadow_git_out"
git -C "$CLIENT_DIR" switch -q msa-242-work

no_home_out="$(printf '%s' "$missing_python_json" | env -u HOME -u FRAM_LOG \
  -u FRAM_TELEMETRY_LOG AGENT_NO_AUTHORING_HOOKS=0 \
  NORTH_CLOCK_GUARD_ATTEST=1 "$HOOK" 2>/dev/null)"
check_output unavailable 'missing HOME and default corpus location fails closed' "$no_home_out"

orphan_telemetry_out="$(printf '%s' "$missing_python_json" | env -u FRAM_LOG \
  FRAM_TELEMETRY_LOG="$SCRATCH/open-msa.log" AGENT_NO_AUTHORING_HOOKS=0 \
  NORTH_CLOCK_GUARD_ATTEST=1 "$HOOK" 2>/dev/null)"
check_output unavailable 'telemetry override without coordination corpus fails closed' "$orphan_telemetry_out"

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
  printf '%s' "$json" | env -u AGENT_NO_AUTHORING_HOOKS \
    -u CLAUDE_NO_AUTHORING_HOOKS -u NORTH_CLOCK_GUARD_ATTEST \
    -u FRAM_LOG -u FRAM_TELEMETRY_LOG \
    HOME="$DEFAULT_HOME" AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
    "$HOOK" 2>/dev/null
}

# Stale facts.log says no clock; the live split says a human msa client session
# is open. The end_time retraction proves exact current-state semantics.
{
  assert_fact 1 '@stale-thread' owner msa
  assert_fact 2 '@stale-thread' linear MSA-321
} > "$DEFAULT_STATE/facts.log"
{
  assert_fact 101 '@live-thread' owner msa
  assert_fact 102 '@live-thread' linear MSA-321
  assert_fact 120 '@live-thread' title 'MSA-321 live'
} > "$DEFAULT_STATE/coordination.log"
{
  assert_fact 103 '@live-client-session' kind client_session
  assert_fact 104 '@live-client-session' owner msa
  assert_fact 105 '@live-client-session' clocked_by user
  assert_fact 106 '@live-client-session' rate 175
  assert_fact 107 '@live-client-session' start_time '2026-07-16T12:00:00Z'
  assert_fact 108 '@live-client-session' end_time '2026-07-16T12:01:00Z'
  fact 109 retract '@live-client-session' end_time '2026-07-16T12:01:00Z'
} > "$DEFAULT_STATE/telemetry.log"
split_out="$(run_default)"
check_output silent 'split trace + re-opened human client session beat stale monolith' "$split_out"

# The same pair remains selectable explicitly for isolated fixtures/instances.
split_json="$(emit_json Edit "$DEFAULT_REPO/api.py")"
split_override_out="$(printf '%s' "$split_json" | env -u AGENT_NO_AUTHORING_HOOKS \
  -u CLAUDE_NO_AUTHORING_HOOKS -u NORTH_CLOCK_GUARD_ATTEST \
  HOME="$DEFAULT_HOME" FRAM_LOG="$DEFAULT_STATE/coordination.log" \
  FRAM_TELEMETRY_LOG="$DEFAULT_STATE/telemetry.log" \
  AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" "$HOOK" 2>/dev/null)"
check_output silent 'explicit FRAM_LOG + FRAM_TELEMETRY_LOG pair is preserved' "$split_override_out"

# Reverse the contradiction: stale facts.log has a human msa session, while the
# live split has only an acme human session. The verdict must use live split data.
{
  assert_fact 1 '@stale-thread' owner msa
  assert_fact 2 '@stale-thread' linear MSA-321
  assert_fact 3 '@stale-client-session' kind client_session
  assert_fact 4 '@stale-client-session' owner msa
  assert_fact 5 '@stale-client-session' clocked_by user
  assert_fact 6 '@stale-client-session' rate 175
  assert_fact 7 '@stale-client-session' start_time '2026-07-16T11:00:00Z'
} > "$DEFAULT_STATE/facts.log"
{
  assert_fact 201 '@live-thread' owner msa
  assert_fact 202 '@live-thread' linear MSA-321
  assert_fact 252 '@live-thread' title 'MSA-321 live'
  assert_fact 250 '@retracted-thread' linear MSA-321
  fact 251 retract '@retracted-thread' linear MSA-321
} > "$DEFAULT_STATE/coordination.log"
{
  assert_fact 203 '@client-session-acme' kind client_session
  assert_fact 204 '@client-session-acme' owner acme
  assert_fact 205 '@client-session-acme' clocked_by user
  assert_fact 206 '@client-session-acme' rate 200
  assert_fact 207 '@client-session-acme' start_time '2026-07-16T12:30:00Z'
} > "$DEFAULT_STATE/telemetry.log"
split_out="$(run_default)"
if [[ ("$split_out" == *'"permissionDecision": "deny"'* ||
       "$split_out" == *'"permissionDecision":"deny"'*) &&
      "$split_out" == *'WRONG client clock'* &&
      "$split_out" == *'client-session-acme'* &&
      "$split_out" != *'stale-client-session'* ]]; then
  pass=$((pass + 1)); echo "PASS  mismatch  live split human-client verdict ignores stale monolith"
else
  fail=$((fail + 1)); echo "FAIL  mismatch  split/hint result: $split_out"
fi

# With the split absent, the legacy monolith remains a supported fallback.
rm -f "$DEFAULT_STATE/coordination.log" "$DEFAULT_STATE/telemetry.log"
{
  assert_fact 301 '@legacy-thread' owner msa
  assert_fact 302 '@legacy-thread' linear MSA-321
  assert_fact 308 '@legacy-thread' title 'MSA-321 legacy'
  assert_fact 303 '@legacy-client-session' kind client_session
  assert_fact 304 '@legacy-client-session' owner msa
  assert_fact 305 '@legacy-client-session' clocked_by user
  assert_fact 306 '@legacy-client-session' rate 175
  assert_fact 307 '@legacy-client-session' start_time '2026-07-16T13:00:00Z'
} > "$DEFAULT_STATE/facts.log"
legacy_out="$(run_default)"
check_output silent 'facts.log fallback supports new human sessions only when split is absent' "$legacy_out"

echo "== explicit kill-switch is the only bypass and never forges attestation =="
ks_json="$(emit_json Edit "$CLIENT_DIR/api.py")"
ks_out="$(printf '%s' "$ks_json" | env -u CLAUDE_NO_AUTHORING_HOOKS \
  AGENT_NO_AUTHORING_HOOKS=1 NORTH_CLOCK_GUARD_ATTEST=1 \
  FRAM_LOG="$SCRATCH/closed.log" AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
  "$HOOK" 2>/dev/null)"
check_output silent 'provider-neutral env kill-switch bypasses silently' "$ks_out"

legacy_ks_out="$(printf '%s' "$ks_json" | env -u AGENT_NO_AUTHORING_HOOKS \
  CLAUDE_NO_AUTHORING_HOOKS=1 NORTH_CLOCK_GUARD_ATTEST=1 \
  FRAM_LOG="$SCRATCH/closed.log" AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
  "$HOOK" 2>/dev/null)"
check_output silent 'legacy env kill-switch remains a silent compatibility bypass' "$legacy_ks_out"

printf '%s\n' 'guards=off' >"$SCRATCH/killswitch.state"
persistent_ks_out="$(printf '%s' "$ks_json" | env -u AGENT_NO_AUTHORING_HOOKS \
  -u CLAUDE_NO_AUTHORING_HOOKS NORTH_CLOCK_GUARD_ATTEST=1 \
  FRAM_LOG="$SCRATCH/closed.log" AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
  "$HOOK" 2>/dev/null)"
check_output silent 'persistent north config state bypasses silently' "$persistent_ks_out"

force_live_out="$(printf '%s' "$ks_json" | env AGENT_NO_AUTHORING_HOOKS=0 \
  NORTH_CLOCK_GUARD_ATTEST=1 FRAM_LOG="$SCRATCH/closed.log" \
  AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" "$HOOK" 2>/dev/null)"
check_output deny 'explicit force-live overrides persistent bypass' "$force_live_out"
printf '%s\n' 'guards=on' >"$SCRATCH/killswitch.state"

if [ "${CLOCK_GUARD_BENCHMARK:-0}" = 1 ]; then
  python3 - "$HOOK" "$SCRATCH/closed.log" "$SCRATCH/open-msa.log" \
    "$SCRATCH/killswitch.state" "$CLIENT_DIR" "$NONCLIENT" <<'PY'
import json
import os
import statistics
import subprocess
import sys
import time

hook, closed, opened, state, client, nonclient = sys.argv[1:]
cases = {
    "not-applicable": (
        {
            "tool_name": "Edit",
            "tool_input": {"file_path": nonclient + "/probe"},
        },
        closed,
        "not-applicable",
    ),
    "exact-clock-allow": (
        {
            "tool_name": "Edit",
            "tool_input": {"file_path": client + "/probe"},
        },
        opened,
        "allow",
    ),
    "exact-clock-deny": (
        {
            "tool_name": "Edit",
            "tool_input": {"file_path": client + "/probe"},
        },
        closed,
        "permissionDecision",
    ),
}
for label, (payload, corpus, marker) in cases.items():
    env = os.environ.copy()
    for key in (
        "AGENT_NO_AUTHORING_HOOKS",
        "CLAUDE_NO_AUTHORING_HOOKS",
        "FRAM_TELEMETRY_LOG",
    ):
        env.pop(key, None)
    env.update({
        "AUTHORING_KILLSWITCH_STATE": state,
        "FRAM_LOG": corpus,
        "NORTH_CLOCK_GUARD_ATTEST": "1",
    })
    encoded = json.dumps(payload)
    samples = []
    for iteration in range(55):
        started = time.perf_counter()
        result = subprocess.run(
            [hook],
            input=encoded,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
            timeout=2,
            check=True,
        )
        elapsed = (time.perf_counter() - started) * 1000
        if marker not in result.stdout:
            raise SystemExit("%s benchmark returned %r" % (label, result.stdout))
        if iteration >= 5:
            samples.append(elapsed)
    ordered = sorted(samples)
    p95 = ordered[max(0, int(len(ordered) * 0.95) - 1)]
    print(
        "BENCH %-18s n=%d p50=%.1fms p95=%.1fms max=%.1fms"
        % (label, len(samples), statistics.median(samples), p95, max(samples))
    )
PY
fi

if [ "${CLOCK_GUARD_LIVE_BENCHMARK:-0}" = 1 ]; then
  live_ticket="${CLOCK_GUARD_LIVE_TICKET:-MSA-247}"
  live_repo="$SCRATCH/live/code/client/msa/repo"
  mkdir -p "$live_repo"
  git -C "$live_repo" init -q -b "${live_ticket,,}-clock-benchmark"
  git -C "$live_repo" -c user.name=test -c user.email=test@example.invalid \
    commit --allow-empty --no-verify -qm init
  python3 - "$HOOK" "$SCRATCH/killswitch.state" "$live_repo" <<'PY'
import json
import os
import statistics
import subprocess
import sys
import time

hook, state, repository = sys.argv[1:]
home = os.environ["HOME"]
corpora = [
    os.path.join(home, ".local/state/north/coordination.log"),
    os.path.join(home, ".local/state/north/telemetry.log"),
]
line_count = 0
byte_count = 0
for path in corpora:
    byte_count += os.path.getsize(path)
    with open(path, "rb") as handle:
        line_count += sum(1 for _line in handle)

env = os.environ.copy()
for key in (
    "AGENT_NO_AUTHORING_HOOKS",
    "CLAUDE_NO_AUTHORING_HOOKS",
    "FRAM_LOG",
    "FRAM_TELEMETRY_LOG",
):
    env.pop(key, None)
env.update({
    "AUTHORING_KILLSWITCH_STATE": state,
    "NORTH_CLOCK_GUARD_ATTEST": "1",
})
encoded = json.dumps({
    "tool_name": "Edit",
    "tool_input": {"file_path": repository + "/probe"},
})
samples = []
corpus_review_bytes = 48 * 1024 * 1024
for iteration in range(55):
    started = time.perf_counter()
    result = subprocess.run(
        [hook],
        input=encoded,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=3,
        check=True,
    )
    elapsed = (time.perf_counter() - started) * 1000
    if '"northClockGuard": "allow"' not in result.stdout:
        raise SystemExit("live benchmark did not resolve an exact clock: %r"
                         % result.stdout)
    if iteration >= 5:
        samples.append(elapsed)
ordered = sorted(samples)
p95 = ordered[max(0, int(len(ordered) * 0.95) - 1)]
maximum = max(samples)
print(
    "LIVE-BENCH corpus=%d-lines/%d-bytes n=%d "
    "p50=%.1fms p95=%.1fms max=%.1fms "
    "budget=corpus<%d-bytes,p95<1000ms,max<2000ms"
    % (
        line_count,
        byte_count,
        len(samples),
        statistics.median(samples),
        p95,
        maximum,
        corpus_review_bytes,
    )
)
if (
    byte_count >= corpus_review_bytes
    or p95 >= 1000
    or maximum >= 2000
):
    raise SystemExit(
        "direct corpus fold exceeded its budget; use an indexed coordinator query"
    )
PY
fi

echo
echo "== result: $pass passed, $fail failed =="
[ "$fail" = 0 ]
