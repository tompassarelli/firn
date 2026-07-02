#!/usr/bin/env bash
# tripwire-guard.sh — PreToolUse deny-hook (Bash tool ONLY; Edit/Write have domain guards).
# =============================================================================
# The self-owned safety layer that must exist BEFORE unattended agents run with
# bypassPermissions: PreToolUse hooks fire even under
# --dangerously-skip-permissions, so this file is the explicit, versioned
# replacement for the opaque built-in permission classifier on unattended runs.
#
# DENY (exit 2 + one-line stderr reason) ONLY these classes; everything else
# exits 0 fast:
#   1. Recursive/force deletes outside safe roots: rm -rf/-fr (any flag order,
#      incl. --recursive --force) whose target resolves outside the cwd repo,
#      /tmp, or /tmp/claude-*; rm -rf of /, /home, ~ denied outright. Also
#      find … -delete with start paths outside those roots, and
#      git -C <elsewhere> clean -f… (plain git clean in the cwd repo: allowed).
#   2. Force-push / history rewrite: git push with -f/--force/--force-with-lease/
#      --mirror/--delete/--prune; and raw `git push` (house policy: safe-push
#      only). safe-push's inner push exports SAFE_PUSH_ACTIVE=1 → allowed.
#   3. Credential exfil surface: a secret-ish path (.ssh/, .aws/, *_SECRET*,
#      *.pem, id_rsa/id_ed25519/id_ecdsa, .config/sops, /run/secrets, *.age)
#      AND a network verb (curl/wget/nc/ncat/netcat/ssh) in the SAME command,
#      non-localhost. Plain local reads of secret paths: ALLOWED — the tripwire
#      is the exfil COMBINATION. ssh/scp `-i <keyfile>` is authentication, not
#      exfil: the token after -i is excluded from the secret scan.
#   4. Outbound uploads: curl/wget with -T/--upload-file/-d @f/--data-binary @f/
#      -F x=@f/--post-file to non-localhost; scp/rsync whose DESTINATION (last
#      non-flag arg) is a remote host not in {github.com, localhost, 127.0.0.1}.
#   5. Destructive system ops: mkfs*, dd of=/dev/* (except null/stdout/stderr),
#      shutdown/reboot/poweroff/halt, systemctl (system, not --user)
#      stop/disable/mask of non-tern* units + power subcommands,
#      chmod -R 000, chown -R root.
#
# Design constraints honored:
#   - pure bash + coreutils; jq only on the slow path for correct JSON string
#     decode (NO python — this runs on EVERY Bash call). Fork budget: fast path
#     0 forks (case-glob prescreen), slow path 2 (jq), deletion classes add one
#     `git rev-parse` + one `realpath -m` per candidate target.
#   - FAIL-OPEN on anything unparseable — this is a tripwire for clear
#     destructive patterns, not a general classifier. Deliberate accepted
#     misses: `bash -c "…"`/xargs indirection, unexpanded $VAR targets,
#     find with \( \) grouping (the grouped -delete lands in another segment).
#   - Every DENY is appended to ~/.local/state/tern/tripwire.log
#     (ISO ts <TAB> cwd <TAB> reason <TAB> command head) so tern-mine can audit.
#
# Test matrix: sibling tripwire-guard.test.sh — run it after EVERY edit here.
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 in the hook env (house parity).
# =============================================================================
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

payload="$(cat 2>/dev/null || true)"
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

command -v jq >/dev/null 2>&1 || exit 0 # fail-open
cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)" || exit 0
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

LOGDIR="${TRIPWIRE_LOG_DIR:-$HOME/.local/state/tern}" # override: tests only
deny() {
  ensure_cwd
  local head="${cmd//$'\n'/ }"
  mkdir -p "$LOGDIR" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' "$(date -Is)" "$cwd" "$1" "${head:0:200}" \
    >>"$LOGDIR/tripwire.log" 2>/dev/null || true
  printf 'tripwire: %s\n' "$1" >&2
  exit 2
}

# ---- tokenize: normalize separators to standalone ";" tokens, then word-split.
# "$(" is split (catches `$(rm -rf /)`); bare "(" is NOT (keeps find \( \) intact);
# strip_g trims a trailing ")" instead. Quoted strings split on spaces — fine for
# detection: dispatch keys off the segment's COMMAND WORD, so words inside quoted
# args (`git commit -m "never push"`) can't false-positive.
norm="$cmd"
norm="${norm//\\$'\n'/ }" # line continuation first — keep the logical line whole
norm="${norm//$'\n'/ ; }"
norm="${norm//$'\t'/ }"
# shellcheck disable=SC2016  # literal $( — command substitution opener in the TEXT
norm="${norm//'$('/ ; }"
norm="${norm//\`/ ; }"
norm="${norm//&&/ ; }"
norm="${norm//'||'/ ; }"
norm="${norm//;/ ; }"
norm="${norm//|/ ; }"
norm="${norm//&/ ; }"
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

# resolve_path TOKEN -> $RES (canonical abs path); return 1 = unresolvable (fail-open).
resolve_path() {
  strip_g "$1"
  local t="$S"
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
      t="$cwd/$t"
      ;;
  esac
  t="${t%%[*?]*}" # glob → its literal prefix (rm -rf /x/* judges /x/)
  case "$t" in
    *'$'* | *'`'*) return 1 ;; # unexpanded substitution mid-path
    '') return 1 ;;
  esac
  # -s: LEXICAL canonicalization only — never follow symlinks. rm on a symlink
  # removes the link, not the target; resolving would false-positive on nix
  # `result` links (they point into /nix/store, "outside" the repo).
  RES="$(realpath -sm -- "$t" 2>/dev/null)" || return 1
  [ -n "$RES" ] || return 1
}

# deny unless target is inside: cwd repo, /tmp, /tmp/claude-*. Root-ish targets outright.
check_delete_target() {
  resolve_path "$1" || return 0
  local p="$RES"
  case "$p" in
    / | /home | /home/tom | "$HOME") deny "recursive delete of '$p' — never, not even by accident" ;;
    /tmp/*) return 0 ;;
  esac
  ensure_repo_root
  if [ -n "$REPO_ROOT" ] && { [ "$p" = "$REPO_ROOT" ] || [[ "$p" == "$REPO_ROOT"/* ]]; }; then
    return 0
  fi
  deny "recursive delete outside safe roots (target: $p; safe: cwd repo, /tmp, /tmp/claude-*)"
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
  case "$S" in
    *.ssh/* | *.aws/* | *_SECRET* | *.pem | *id_rsa* | *id_ed25519* | *id_ecdsa* | \
      *.config/sops* | */run/secrets* | *.age)
      SECRET_HIT=1 ;;
  esac
  prev="$S"
done
unset prev

secret_exfil_check() { # $1 = network verb (for the message)
  [ "$SECRET_HIT" = 1 ] || return 0
  [ "$LOCALHOST_HIT" = 1 ] && return 0
  deny "secret path + network verb '$1' in one command — credential exfil surface (local reads alone are fine)"
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

handle_rm() {
  local recursive=0 force=0 endflags=0 skipnext=0 t
  local -a targets=()
  for t in "$@"; do
    if [ "$skipnext" = 1 ]; then skipnext=0; continue; fi
    redirect_skip "$t"
    if [ "$REDIR" = 1 ]; then skipnext="$REDIR_NEXT"; continue; fi
    if [ "$endflags" = 1 ]; then targets+=("$t"); continue; fi
    case "$t" in
      --) endflags=1 ;;
      --recursive) recursive=1 ;;
      --force) force=1 ;;
      --*) ;;
      -*[rR]*)
        recursive=1
        case "$t" in *f*) force=1 ;; esac
        ;;
      -*f*) force=1 ;;
      -*) ;;
      *) targets+=("$t") ;;
    esac
  done
  { [ "$recursive" = 1 ] && [ "$force" = 1 ]; } || return 0
  for t in "${targets[@]}"; do check_delete_target "$t"; done
}

handle_find() {
  local has_delete=0 t
  for t in "$@"; do [ "$t" = "-delete" ] && has_delete=1; done
  [ "$has_delete" = 1 ] || return 0
  local -a paths=()
  for t in "$@"; do
    case "$t" in
      -H | -L | -P | -O*) ;;
      -* | '!'* | '('* | \\* | *'<'* | *'>'*) break ;;
      *) paths+=("$t") ;;
    esac
  done
  [ "${#paths[@]}" -gt 0 ] || paths=(".") # find defaults to cwd
  for t in "${paths[@]}"; do check_delete_target "$t"; done
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
      # Branch DELETION is not history rewrite (2026-07-03, Tom): a deleted branch
      # pointer loses nothing merged, and reflog/clones keep the commits. Allowed
      # without safe-push — there are no outgoing commits to secret-scan.
      [ "$del" = 1 ] && return 0
      [ -n "${SAFE_PUSH_ACTIVE:-}" ] && return 0 # safe-push's own inner push
      deny "raw 'git push' — house policy: use safe-push (gitleaks-scans the outgoing commits, then pushes)"
      ;;
    clean)
      for ((j = i + 1; j < n; j++)); do
        case "${a[$j]}" in --force | -*f*) force=1 ;; esac
      done
      [ "$force" = 1 ] || return 0
      [ -n "$cval" ] || return 0 # plain `git clean -f…` cleans the cwd repo: allowed
      resolve_path "$cval" || return 0
      case "$RES" in /tmp/*) return 0 ;; esac
      ensure_repo_root
      if [ -n "$REPO_ROOT" ] && { [ "$RES" = "$REPO_ROOT" ] || [[ "$RES" == "$REPO_ROOT"/* ]]; }; then
        return 0
      fi
      deny "git -C clean -f outside the cwd repo (target: $RES)"
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

handle_scp_rsync() { # destination = LAST non-flag arg; downloads (remote src) stay allowed
  local verb="$1" t dest="" skipnext=0
  shift
  for t in "$@"; do
    if [ "$skipnext" = 1 ]; then skipnext=0; continue; fi
    redirect_skip "$t"
    if [ "$REDIR" = 1 ]; then skipnext="$REDIR_NEXT"; continue; fi
    strip_g "$t"
    case "$S" in -*) ;; *) dest="$S" ;; esac
  done
  [ -n "$dest" ] || return 0
  local h=""
  case "$dest" in
    rsync://*)
      h="${dest#rsync://}"
      h="${h%%/*}"
      ;;
    /* | ./* | ../*) return 0 ;;
    *:*) h="${dest%%:*}" ;;
    *) return 0 ;;
  esac
  h="${h#*@}"
  case "$h" in
    '' | localhost | 127.0.0.1 | ::1 | github.com) return 0 ;;
    *[!A-Za-z0-9._-]*) return 0 ;; # not a hostname → fail-open
  esac
  deny "$verb to remote host '$h' — not in allowlist (github.com, localhost)"
}

handle_systemctl() {
  local user=0 sub="" t
  local -a units=()
  for t in "$@"; do
    case "$t" in
      --user) user=1 ;;
      -*) ;;
      *) if [ -z "$sub" ]; then sub="$t"; else units+=("$t"); fi ;;
    esac
  done
  [ "$user" = 1 ] && return 0
  case "$sub" in
    poweroff | reboot | halt | kexec | suspend | hibernate)
      deny "systemctl $sub — system power ops are manual"
      ;;
    stop | disable | mask) ;;
    *) return 0 ;;
  esac
  [ "${#units[@]}" -gt 0 ] || return 0
  for t in "${units[@]}"; do
    strip_g "$t"
    case "$S" in
      tern*) ;;
      *) deny "systemctl $sub $S — stopping/disabling system units is manual (tern* only)" ;;
    esac
  done
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

# ---- segment walk: find each segment's command word, dispatch with its args.
i=0
n="${#TOK[@]}"
while [ "$i" -lt "$n" ]; do
  t="${TOK[$i]}"
  if [ "$t" = ";" ]; then
    i=$((i + 1))
    continue
  fi
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
  while [ "$j" -lt "$n" ] && [ "${TOK[$j]}" != ";" ]; do
    args+=("${TOK[$j]}")
    j=$((j + 1))
  done
  case "$word" in
    rm) handle_rm ${args[@]+"${args[@]}"} ;;
    find) handle_find ${args[@]+"${args[@]}"} ;;
    git) handle_git ${args[@]+"${args[@]}"} ;;
    curl | wget) handle_http "$word" ${args[@]+"${args[@]}"} ;;
    nc | ncat | netcat) secret_exfil_check "$word" ;;
    ssh) secret_exfil_check "ssh" ;;
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

exit 0
