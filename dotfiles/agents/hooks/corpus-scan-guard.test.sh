#!/usr/bin/env bash
# Adversarial matrix for corpus-scan-guard: the corpus-wide sweep is refused
# and names `convo`, while every narrow shape an agent legitimately needs —
# one transcript, one day, one project, a bounded find, a plain grep — still
# runs. The fixture builds a fake corpus under a sandbox HOME so the geometry
# under test is the directory shape, never the live 99 GB tree.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/corpus-scan-guard.sh"

SB="$(mktemp -d "${TMPDIR:-/tmp}/corpus-scan-guard-test.XXXXXX")"
trap 'rm -rf "${SB:?}"' EXIT
HOME_SB="$SB/home"
ND="$HOME_SB/code/north-data"
SESS="$ND/accounts/openai/codex-personal-apple/sessions/2026/08/12"
PROJ="$ND/accounts/anthropic/claude-acct/projects/-home-tom-code-north"
mkdir -p "$SESS" "$PROJ" "$ND/archives/zero-slate" "$ND/threads" \
  "$HOME_SB/.local/state" "$HOME_SB/code/north/main"
ln -sfn "$ND" "$HOME_SB/.local/state/north"
ROLLOUT="$SESS/rollout-2026-08-12T13-42-23-019ff47e.jsonl"
: > "$ROLLOUT"
: > "$PROJ/f1854f2e.jsonl"
: > "$ND/README.md"

pass=0 fail=0

decide() { # command [cwd]
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
    "$1" "${2:-$HOME_SB}" |
    env HOME="$HOME_SB" \
      NORTH_HARNESS_STATE="$SB/harness.conf" AGENT_NO_AUTHORING_HOOKS=0 "$GUARD"
}

verdict() { # raw-output
  python3 -c 'import json,sys
raw = sys.argv[1].strip()
if not raw:
    print("allow"); raise SystemExit
try:
    d = json.loads(raw)
except Exception:
    print("malformed"); raise SystemExit
o = d.get("hookSpecificOutput", {})
print(o.get("permissionDecision", "allow"))' "$1"
}

# A deny must also name the compliant move; a guard that only says no is a trap.
deny() { # desc command [cwd]
  local desc="$1" cmd="$2" out v
  out="$(decide "$cmd" "${3:-}")"
  v="$(verdict "$out")"
  if [ "$v" = deny ] && [[ "$out" == *convo* ]]; then
    pass=$((pass + 1)); printf 'PASS  deny   %s\n' "$desc"
  else
    fail=$((fail + 1)); printf 'FAIL  deny   %s\n      got=%s out=%s\n' "$desc" "$v" "$out"
  fi
}

allow() { # desc command [cwd]
  local desc="$1" cmd="$2" out v
  out="$(decide "$cmd" "${3:-}")"
  v="$(verdict "$out")"
  if [ "$v" = allow ]; then
    pass=$((pass + 1)); printf 'PASS  allow  %s\n' "$desc"
  else
    fail=$((fail + 1)); printf 'FAIL  allow  %s\n      got=%s out=%s\n' "$desc" "$v" "$out"
  fi
}

echo '== the expensive shape is refused, however it is spelled =='
deny 'unscoped rg at the corpus root' "rg -l --hidden needle $ND"
deny 'the symlink is the same tree' "grep -rn needle $HOME_SB/.local/state/north"
deny 'naming both scans it twice' "rg -l needle $ND $HOME_SB/.local/state/north"
deny 'accounts container' "rg needle $ND/accounts"
deny 'one provider' "rg needle $ND/accounts/openai"
deny 'one account' "rg needle $ND/accounts/openai/codex-personal-apple"
deny 'the sessions container' "rg needle $ND/accounts/openai/codex-personal-apple/sessions"
deny 'a sessions year' "rg needle $ND/accounts/openai/codex-personal-apple/sessions/2026"
deny 'a sessions month' "rg needle $ND/accounts/openai/codex-personal-apple/sessions/2026/08"
deny 'the projects container' "rg needle $ND/accounts/anthropic/claude-acct/projects"
deny 'the archives root' "rg needle $ND/archives"
deny 'unbounded find over the corpus' "find $ND -name 'rollout-*.jsonl'"
deny 'find piped into grep' "find $ND -type f | xargs grep -l needle"
deny 'recursive grep' "grep -R needle $ND"
deny 'glob across accounts' "rg needle $ND/accounts/*/*/sessions"
deny 'behind a wrapper' "nice -n 15 rg needle $ND"
deny 'behind sudo' "sudo rg needle $ND"
deny 'after a separator' "printf ready && rg needle $ND"
deny 'after --' "rg needle -- $ND"
deny 'cwd is the corpus, no operand' 'rg -l needle' "$ND"
deny 'cd into the corpus first' "cd $ND && rg -l needle ."

echo
echo '== every narrow shape an agent needs still runs =='
allow 'one known transcript file' "rg needle $ROLLOUT"
allow 'one transcript, plain grep' "grep needle $ROLLOUT"
allow 'a single day directory' "rg needle $SESS"
allow 'below a day directory' "rg needle $SESS/nested"
allow 'a single Claude project directory' "rg needle $PROJ"
allow 'cwd is one day directory' 'rg -l needle' "$SESS"
allow 'a named archive' "rg needle $ND/archives/zero-slate"
allow 'a non-transcript subtree' "rg needle $ND/threads"
allow 'bounded find' "find $ND -maxdepth 2 -type d"
allow 'bounded rg' "rg --max-depth 2 needle $ND"
allow 'non-recursive grep never walks' "grep needle $ND/README.md"
allow 'listing is not searching' "ls -la $ND/accounts"
allow 'stat is not searching' "stat $ND/accounts/openai"
allow 'du is not searching' "du -sh $ND/accounts"
allow 'reading a known file' "cat $ND/README.md"
allow 'convo itself' "convo -x 'some literal'"
allow 'convo session lookup' 'convo session 019ff47e-4216-7de0-8308-4c88d9427a7a'
allow 'searching a different repo' "rg needle $HOME_SB/code/north/main"

echo
echo '== a mention is not an invocation =='
allow 'prose in an echo' "echo 'never rg $ND again'"
allow 'a commit message' "git commit -m \"stop rg over $ND\""
allow 'the corpus path as a PATTERN' "rg -x '$ND' $HOME_SB/notes.md"
allow 'a heredoc body' "$(printf 'cat <<%s\nrg -l needle %s\nEOF\n' EOF "$ND")"

echo
echo '== envelopes this guard has no opinion on =='
out="$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":sys.argv[1]}}))' "$ND/x" |
  env HOME="$HOME_SB" AGENT_NO_AUTHORING_HOOKS=0 "$GUARD")"
if [ "$(verdict "$out")" = allow ]; then
  pass=$((pass + 1)); printf 'PASS  allow  an Edit envelope is not a search\n'
else
  fail=$((fail + 1)); printf 'FAIL  allow  an Edit envelope is not a search — %s\n' "$out"
fi
out="$(printf 'not json at all' | env HOME="$HOME_SB" AGENT_NO_AUTHORING_HOOKS=0 "$GUARD")"
if [ "$(verdict "$out")" = allow ]; then
  pass=$((pass + 1)); printf 'PASS  allow  a malformed envelope fails open\n'
else
  fail=$((fail + 1)); printf 'FAIL  allow  a malformed envelope fails open — %s\n' "$out"
fi

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
