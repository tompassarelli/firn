#!/usr/bin/env bash
# shellcheck disable=SC2016 # Dollar-prefixed names in single quotes are jq variables.
set -uo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
GIT_BIN="${GIT_BIN:-git}"
JQ_BIN="${JQ_BIN:-jq}"
TIMEOUT_BIN="${TIMEOUT_BIN:-timeout}"
FLOCK_BIN="${FLOCK_BIN:-flock}"
MV_BIN="${MV_BIN:-mv}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"
PS_BIN="${PS_BIN:-ps}"
WC_BIN="${WC_BIN:-wc}"
GAFFER_HOME="${GAFFER_HOME:-$HOME/code/gaffer}"
GAFFER_SOURCE="${GAFFER_SOURCE:-$HOME/.local/state/north/gaffer-plugin-source}"
GAFFER_LOCK="${GAFFER_LOCK:-$HOME/.local/state/north/gaffer-plugin-source.lock}"
GAFFER_INTENT="${GAFFER_INTENT:-$GAFFER_SOURCE.intent}"
GAFFER_REV="${GAFFER_REV:-}"
LOCK_TIMEOUT_SECONDS="${LOCK_TIMEOUT_SECONDS:-45}"
LIST_TIMEOUT_SECONDS="${LIST_TIMEOUT_SECONDS:-10}"
MUTATION_TIMEOUT_SECONDS="${MUTATION_TIMEOUT_SECONDS:-30}"
KILL_AFTER_SECONDS="${KILL_AFTER_SECONDS:-2}"
BOUND_POLL_SECONDS="${BOUND_POLL_SECONDS:-0.02}"
MAX_OUTPUT_KIB="${MAX_OUTPUT_KIB:-256}"
PLUGIN_ID="gaffer@gaffer"
MANAGED_MARKER_NAME="north-managed-gaffer-plugin-source"
MANAGED_MARKER_VALUE="north-gaffer-plugin-source-v1"
INTENT_VERSION="north-gaffer-plugin-source-intent-v1"
BOUNDED_CHILD_MODE="--north-gaffer-bounded-child-v1"
SYNC_SCRIPT_PATH="${BASH_SOURCE[0]}"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

is_positive_decimal() {
  local value="$1"

  [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
    [ -n "${value//[0.]/}" ]
}

hold_bounded_group() {
  trap '' TERM
  while :; do
    "$SLEEP_BIN" 3600 || true
  done
}

# GNU timeout normally stops supervising once its direct child exits, which
# can leak a TERM-resistant descendant. This child records the command result
# atomically but stays alive as the process-group anchor. The parent kills the
# whole group after a normal result; on timeout, the anchor survives TERM so
# timeout's --kill-after necessarily reaps the group with KILL.
bounded_child_main() {
  local pid_file="$1" status_file="$2" stdout_file="$3" stderr_file="$4"
  local command_pid command_status term_observed=0 temp
  shift 4
  [ "$#" -gt 0 ] || exit 125

  temp="$(mktemp "${pid_file}.tmp.XXXXXX")" || exit 125
  printf '%s\n' "$$" >"$temp" || exit 125
  command mv "$temp" "$pid_file" || exit 125

  trap 'term_observed=1' TERM
  (
    ulimit -f "$MAX_OUTPUT_KIB" || exit 125
    exec "$@"
  ) >"$stdout_file" 2>"$stderr_file" &
  command_pid=$!
  wait "$command_pid" 2>>"$stderr_file"
  command_status=$?
  if [ "$term_observed" -eq 1 ]; then
    hold_bounded_group
  fi

  temp="$(mktemp "${status_file}.tmp.XXXXXX")" || exit 125
  printf '%s\n' "$command_status" >"$temp" || exit 125
  command mv "$temp" "$status_file" || exit 125
  hold_bounded_group
}

run_bounded_cli() {
  local duration="$1" scratch pid_file status_file stdout_file stderr_file
  local timeout_pid timeout_status timeout_pgid leader leader_pgid command_status
  local stdout_size stderr_size max_output_bytes
  shift

  is_positive_decimal "$duration" ||
    die "bounded command duration must be a positive number"
  is_positive_decimal "$KILL_AFTER_SECONDS" ||
    die "KILL_AFTER_SECONDS must be a positive number"
  is_positive_decimal "$BOUND_POLL_SECONDS" ||
    die "BOUND_POLL_SECONDS must be a positive number"
  [[ "$MAX_OUTPUT_KIB" =~ ^[1-9][0-9]*$ ]] ||
    die "MAX_OUTPUT_KIB must be a positive integer"
  max_output_bytes=$((MAX_OUTPUT_KIB * 1024))
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/gaffer-bounded.XXXXXX")" ||
    die "could not create bounded-command state"
  pid_file="$scratch/leader"
  status_file="$scratch/status"
  stdout_file="$scratch/stdout"
  stderr_file="$scratch/stderr"

  "$TIMEOUT_BIN" --signal=TERM --kill-after="$KILL_AFTER_SECONDS" \
    "$duration" "$SYNC_SCRIPT_PATH" "$BOUNDED_CHILD_MODE" \
    "$pid_file" "$status_file" "$stdout_file" "$stderr_file" "$@" &
  timeout_pid=$!
  while [ ! -s "$status_file" ] && kill -0 "$timeout_pid" 2>/dev/null; do
    "$SLEEP_BIN" "$BOUND_POLL_SECONDS"
  done

  if [ -s "$status_file" ]; then
    IFS= read -r leader <"$pid_file" || leader=''
    IFS= read -r command_status <"$status_file" || command_status=''
    timeout_pgid="$("$PS_BIN" -o pgid= -p "$timeout_pid" 2>/dev/null || true)"
    leader_pgid="$("$PS_BIN" -o pgid= -p "$leader" 2>/dev/null || true)"
    timeout_pgid="${timeout_pgid//[[:space:]]/}"
    leader_pgid="${leader_pgid//[[:space:]]/}"
    if [[ "$leader" =~ ^[1-9][0-9]*$ ]] &&
       [[ "$command_status" =~ ^[0-9]+$ ]] &&
       [ "$command_status" -le 255 ] &&
       [ "$timeout_pgid" = "$timeout_pid" ] &&
       [ "$leader_pgid" = "$timeout_pid" ]; then
      kill -KILL -- "-$timeout_pid" 2>/dev/null || true
      wait "$timeout_pid" 2>/dev/null || true
      stdout_size="$("$WC_BIN" -c <"$stdout_file" 2>/dev/null || printf invalid)"
      stderr_size="$("$WC_BIN" -c <"$stderr_file" 2>/dev/null || printf invalid)"
      if
       [[ "$stdout_size" =~ ^[0-9]+$ ]] &&
       [[ "$stderr_size" =~ ^[0-9]+$ ]] &&
       [ "$stdout_size" -lt "$max_output_bytes" ] &&
       [ "$stderr_size" -lt "$max_output_bytes" ]
      then
        if [ -s "$stderr_file" ]; then
          command cat "$stderr_file" >&2
        fi
        if [ -f "$stdout_file" ]; then
          command cat "$stdout_file"
        fi
        rm -rf "$scratch"
        return "$command_status"
      fi
      rm -rf "$scratch"
      return 125
    fi
  fi

  wait "$timeout_pid"
  timeout_status=$?
  rm -rf "$scratch"
  case "$timeout_status" in
    0) return 125 ;;
    124|137) return 124 ;;
  esac
  return "$timeout_status"
}

require_exact_revision() {
  local resolved

  [[ "$GAFFER_REV" =~ ^[0-9a-f]{40}$ ]] ||
    die "GAFFER_REV must be the exact 40-character revision from inputs.gaffer.rev"
  resolved="$("$GIT_BIN" -C "$GAFFER_HOME" rev-parse --verify "$GAFFER_REV^{commit}" 2>/dev/null)" ||
    die "Gaffer revision $GAFFER_REV is not present in $GAFFER_HOME"
  [ "$resolved" = "$GAFFER_REV" ] ||
    die "Gaffer revision resolved to $resolved, expected $GAFFER_REV"
}

acquire_sync_lock() {
  local lock_parent

  [[ "$LOCK_TIMEOUT_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
    die "LOCK_TIMEOUT_SECONDS must be a nonnegative number"
  lock_parent="${GAFFER_LOCK%/*}"
  [ "$lock_parent" != "$GAFFER_LOCK" ] ||
    die "GAFFER_LOCK must be an absolute managed path"
  mkdir -p "$lock_parent" ||
    die "could not create Gaffer sync-lock parent $lock_parent"
  [ ! -L "$GAFFER_LOCK" ] ||
    die "Gaffer sync lock $GAFFER_LOCK is a symlink; refusing to follow it"
  exec {SYNC_LOCK_FD}>>"$GAFFER_LOCK" ||
    die "could not open Gaffer sync lock $GAFFER_LOCK"
  "$FLOCK_BIN" -w "$LOCK_TIMEOUT_SECONDS" "$SYNC_LOCK_FD" ||
    die "timed out waiting ${LOCK_TIMEOUT_SECONDS}s for Gaffer plugin sync lock"
}

write_owned_file_once() {
  local path="$1" content="$2" temp

  [ ! -e "$path" ] && [ ! -L "$path" ] ||
    die "refusing to replace existing ownership file $path"
  temp="$(mktemp "${path}.tmp.XXXXXX")" ||
    die "could not create temporary ownership file beside $path"
  if ! printf '%s\n' "$content" >"$temp"; then
    rm -f "$temp"
    die "could not write temporary ownership file for $path"
  fi
  if ! ln "$temp" "$path"; then
    rm -f "$temp"
    die "could not publish ownership file $path without clobbering"
  fi
  rm -f "$temp"
}

read_intent() {
  local home_common intent_json

  [ -f "$GAFFER_INTENT" ] && [ ! -L "$GAFFER_INTENT" ] ||
    die "Gaffer managed-source intent is missing or not a regular owned file: $GAFFER_INTENT"
  intent_json="$("$JQ_BIN" -ce '
    if type == "object"
       and (keys | sort) == ["commonDir", "revision", "source", "version"]
       and (.version | type) == "string"
       and (.source | type) == "string"
       and (.commonDir | type) == "string"
       and (.revision | type) == "string"
    then .
    else error("invalid managed-source intent")
    end
  ' "$GAFFER_INTENT" 2>/dev/null)" ||
    die "Gaffer managed-source intent is malformed: $GAFFER_INTENT"
  INTENT_SOURCE="$("$JQ_BIN" -r '.source' <<<"$intent_json")"
  INTENT_COMMON_DIR="$("$JQ_BIN" -r '.commonDir' <<<"$intent_json")"
  INTENT_REVISION="$("$JQ_BIN" -r '.revision' <<<"$intent_json")"
  INTENT_FILE_VERSION="$("$JQ_BIN" -r '.version' <<<"$intent_json")"
  [ "$INTENT_FILE_VERSION" = "$INTENT_VERSION" ] ||
    die "Gaffer managed-source intent has unknown version '$INTENT_FILE_VERSION'"
  [ "$INTENT_SOURCE" = "$GAFFER_SOURCE" ] ||
    die "Gaffer managed-source intent owns $INTENT_SOURCE, not $GAFFER_SOURCE"
  home_common="$("$GIT_BIN" -C "$GAFFER_HOME" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "Gaffer repository common directory could not be resolved"
  [ "$INTENT_COMMON_DIR" = "$home_common" ] ||
    die "Gaffer managed-source intent names $INTENT_COMMON_DIR, not $home_common"
  [[ "$INTENT_REVISION" =~ ^[0-9a-f]{40}$ ]] ||
    die "Gaffer managed-source intent revision is not exact"
}

encode_intent() {
  local revision="$1" home_common

  home_common="$("$GIT_BIN" -C "$GAFFER_HOME" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "Gaffer repository common directory could not be resolved"
  "$JQ_BIN" -cn \
    --arg version "$INTENT_VERSION" \
    --arg source "$GAFFER_SOURCE" \
    --arg commonDir "$home_common" \
    --arg revision "$revision" \
    '{version:$version,source:$source,commonDir:$commonDir,revision:$revision}' ||
    die "could not encode Gaffer managed-source intent"
}

create_intent() {
  local revision="$1" intent_json

  intent_json="$(encode_intent "$revision")" || exit
  write_owned_file_once "$GAFFER_INTENT" "$intent_json"
  read_intent
}

converge_intent_revision() {
  local revision="$1" intent_json temp

  read_intent
  [ "$INTENT_REVISION" = "$revision" ] && return 0
  intent_json="$(encode_intent "$revision")" || exit
  temp="$(mktemp "${GAFFER_INTENT}.tmp.XXXXXX")" ||
    die "could not create temporary Gaffer managed-source intent"
  if ! printf '%s\n' "$intent_json" >"$temp"; then
    rm -f "$temp"
    die "could not write replacement Gaffer managed-source intent"
  fi
  if ! "$MV_BIN" -T "$temp" "$GAFFER_INTENT"; then
    rm -f "$temp"
    die "could not atomically converge Gaffer managed-source intent"
  fi
  read_intent
  [ "$INTENT_REVISION" = "$revision" ] ||
    die "Gaffer managed-source intent did not converge to $revision"
}

prepare_intent_for_creation() {
  if [ -e "$GAFFER_INTENT" ] || [ -L "$GAFFER_INTENT" ]; then
    read_intent
    if [ "$INTENT_REVISION" != "$GAFFER_REV" ]; then
      rm "$GAFFER_INTENT" ||
        die "could not retire stale Gaffer managed-source intent"
      create_intent "$GAFFER_REV"
    fi
  else
    create_intent "$GAFFER_REV"
  fi
}

read_managed_git_dir() {
  "$GIT_BIN" -C "$GAFFER_SOURCE" rev-parse --path-format=absolute --git-dir 2>/dev/null ||
    die "$GAFFER_SOURCE is not a managed Gaffer worktree"
}

ensure_managed_worktree_lock() {
  local line in_record=0 saw_record=0 lock_reason=''

  while IFS= read -r line; do
    case "$line" in
      "worktree $GAFFER_SOURCE")
        in_record=1
        saw_record=1
        ;;
      worktree\ *)
        in_record=0
        ;;
      locked)
        if [ "$in_record" -eq 1 ]; then
          lock_reason='<no reason>'
        fi
        ;;
      locked\ *)
        if [ "$in_record" -eq 1 ]; then
          lock_reason="${line#locked }"
        fi
        ;;
    esac
  done < <("$GIT_BIN" -C "$GAFFER_HOME" worktree list --porcelain)
  [ "$saw_record" -eq 1 ] ||
    die "$GAFFER_SOURCE is not registered as a Gaffer worktree"
  if [ -z "$lock_reason" ]; then
    "$GIT_BIN" -C "$GAFFER_HOME" worktree lock \
      --reason "$MANAGED_MARKER_VALUE" "$GAFFER_SOURCE" ||
      die "could not protect managed Gaffer worktree from prune/removal"
  elif [ "$lock_reason" != "$MANAGED_MARKER_VALUE" ]; then
    die "$GAFFER_SOURCE has unknown Git worktree lock '$lock_reason'"
  fi
}

require_managed_identity() {
  local source_top source_common home_common managed_git_dir marker dirty head source_ref

  [ -d "$GAFFER_SOURCE" ] ||
    die "$GAFFER_SOURCE exists but is not a directory managed by this sync"
  read_intent
  source_top="$("$GIT_BIN" -C "$GAFFER_SOURCE" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)" ||
    die "$GAFFER_SOURCE exists but is not a Git worktree"
  [ "$source_top" = "$GAFFER_SOURCE" ] ||
    die "$GAFFER_SOURCE resolves to unexpected worktree root $source_top"
  source_common="$("$GIT_BIN" -C "$GAFFER_SOURCE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "Gaffer managed worktree common directory could not be resolved"
  home_common="$("$GIT_BIN" -C "$GAFFER_HOME" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "Gaffer repository common directory could not be resolved"
  [ "$source_common" = "$home_common" ] ||
    die "$GAFFER_SOURCE is a worktree of $source_common, not $GAFFER_HOME"
  managed_git_dir="$(read_managed_git_dir)" || exit
  marker=''
  if [ -f "$managed_git_dir/$MANAGED_MARKER_NAME" ] &&
     [ ! -L "$managed_git_dir/$MANAGED_MARKER_NAME" ]; then
    IFS= read -r marker <"$managed_git_dir/$MANAGED_MARKER_NAME" ||
      die "Gaffer managed-worktree marker could not be read"
  elif [ -e "$managed_git_dir/$MANAGED_MARKER_NAME" ] ||
       [ -L "$managed_git_dir/$MANAGED_MARKER_NAME" ]; then
    die "$GAFFER_SOURCE has an invalid managed-worktree marker"
  fi
  if [ -z "$marker" ]; then
    "$GIT_BIN" -C "$GAFFER_HOME" cat-file -e "$INTENT_REVISION^{commit}" 2>/dev/null ||
      die "recoverable Gaffer intent revision $INTENT_REVISION is unavailable"
    dirty="$("$GIT_BIN" -C "$GAFFER_SOURCE" status --porcelain --untracked-files=all 2>/dev/null)" ||
      die "recoverable Gaffer worktree status could not be read"
    head="$("$GIT_BIN" -C "$GAFFER_SOURCE" rev-parse --verify HEAD 2>/dev/null)" ||
      die "recoverable Gaffer worktree HEAD could not be read"
    source_ref="$("$GIT_BIN" -C "$GAFFER_SOURCE" symbolic-ref --quiet HEAD 2>/dev/null || true)"
    [ -z "$dirty" ] && [ -z "$source_ref" ] &&
      [ "$head" = "$INTENT_REVISION" ] ||
      die "$GAFFER_SOURCE lacks its marker and does not match the durable creation intent"
    write_owned_file_once \
      "$managed_git_dir/$MANAGED_MARKER_NAME" "$MANAGED_MARKER_VALUE"
    marker="$MANAGED_MARKER_VALUE"
  fi
  [ "$marker" = "$MANAGED_MARKER_VALUE" ] ||
    die "$GAFFER_SOURCE has an unknown managed-worktree marker"
  ensure_managed_worktree_lock
}

materialize_managed_source() {
  local managed_parent managed_git_dir dirty head

  if [ -e "$GAFFER_SOURCE" ] || [ -L "$GAFFER_SOURCE" ]; then
    require_managed_identity
  else
    managed_parent="${GAFFER_SOURCE%/*}"
    [ "$managed_parent" != "$GAFFER_SOURCE" ] ||
      die "GAFFER_SOURCE must be an absolute managed path"
    mkdir -p "$managed_parent" ||
      die "could not create Gaffer managed-source parent $managed_parent"
    prepare_intent_for_creation
    "$GIT_BIN" -C "$GAFFER_HOME" worktree add --detach "$GAFFER_SOURCE" "$GAFFER_REV" \
      >/dev/null ||
      die "could not create detached Gaffer worktree at $GAFFER_SOURCE"
    managed_git_dir="$(read_managed_git_dir)" || exit
    write_owned_file_once \
      "$managed_git_dir/$MANAGED_MARKER_NAME" "$MANAGED_MARKER_VALUE"
    require_managed_identity
  fi

  dirty="$("$GIT_BIN" -C "$GAFFER_SOURCE" status --porcelain --untracked-files=all 2>/dev/null)" ||
    die "Gaffer managed-source status could not be read"
  [ -z "$dirty" ] ||
    die "$GAFFER_SOURCE has unexpected tracked or untracked changes; refusing to clobber it"
  head="$("$GIT_BIN" -C "$GAFFER_SOURCE" rev-parse --verify HEAD 2>/dev/null)" ||
    die "Gaffer managed-source HEAD could not be resolved"
  if [ "$head" != "$GAFFER_REV" ]; then
    "$GIT_BIN" -C "$GAFFER_SOURCE" checkout --detach "$GAFFER_REV" >/dev/null ||
      die "could not detach $GAFFER_SOURCE at exact revision $GAFFER_REV"
  fi
  if "$GIT_BIN" -C "$GAFFER_SOURCE" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    die "$GAFFER_SOURCE is attached to a branch; refusing to repurpose it"
  fi
  head="$("$GIT_BIN" -C "$GAFFER_SOURCE" rev-parse --verify HEAD 2>/dev/null)" ||
    die "Gaffer managed-source HEAD could not be re-read"
  [ "$head" = "$GAFFER_REV" ] ||
    die "Gaffer managed source is at $head, expected exact revision $GAFFER_REV"
  dirty="$("$GIT_BIN" -C "$GAFFER_SOURCE" status --porcelain --untracked-files=all 2>/dev/null)" ||
    die "Gaffer managed-source status could not be re-read"
  [ -z "$dirty" ] ||
    die "$GAFFER_SOURCE changed while its exact revision was being materialized"
  converge_intent_revision "$head"
}

require_commit_version_contract() {
  "$JQ_BIN" -e 'has("version") | not' \
    "$GAFFER_SOURCE/.claude-plugin/plugin.json" >/dev/null ||
    die "Gaffer plugin.json must omit version so Claude resolves the Git commit"
  "$JQ_BIN" -e '
    [.plugins[] | select(.name == "gaffer")] as $matches
    | ($matches | length) == 1
      and ($matches[0] | has("version") | not)
  ' "$GAFFER_SOURCE/.claude-plugin/marketplace.json" >/dev/null ||
    die "Gaffer marketplace must contain one unversioned gaffer entry"
}

read_plugin_state() {
  local json="$1"
  PLUGIN_COUNT="$("$JQ_BIN" -er --arg id "$PLUGIN_ID" \
    'if type == "array" then [.[] | select(.id == $id)] | length
     else error("Claude plugin list did not return an array")
     end' <<<"$json")" || die "Claude plugin list returned invalid JSON"
  case "$PLUGIN_COUNT" in
    0)
      PLUGIN_VERSION=''
      ;;
    1)
      PLUGIN_VERSION="$("$JQ_BIN" -er --arg id "$PLUGIN_ID" \
        '.[] | select(.id == $id) | .version | strings' <<<"$json")" ||
        die "Claude Gaffer plugin has no version"
      ;;
    *)
      die "Claude reports $PLUGIN_COUNT installed Gaffer plugin records; expected at most one"
      ;;
  esac
}

read_marketplace_state() {
  local json="$1" source path install_location

  MARKETPLACE_COUNT="$("$JQ_BIN" -er '
    if type == "array"
    then [.[] | select(.name == "gaffer")] | length
    else error("Claude marketplace list did not return an array")
    end
  ' <<<"$json")" || die "Claude marketplace list returned invalid JSON"
  case "$MARKETPLACE_COUNT" in
    0)
      MARKETPLACE_STATE='absent'
      ;;
    1)
      source="$("$JQ_BIN" -er \
        '.[] | select(.name == "gaffer") | .source | strings' <<<"$json")" ||
        die "Claude Gaffer marketplace has no source kind"
      path="$("$JQ_BIN" -er \
        '.[] | select(.name == "gaffer") | .path | strings' <<<"$json")" ||
        die "Claude Gaffer marketplace has no source path"
      install_location="$("$JQ_BIN" -er \
        '.[] | select(.name == "gaffer") | .installLocation | strings' <<<"$json")" ||
        die "Claude Gaffer marketplace has no install location"
      if [ "$source" != directory ] || [ "$install_location" != "$path" ]; then
        MARKETPLACE_STATE='conflict'
      elif [ "$path" = "$GAFFER_SOURCE" ]; then
        MARKETPLACE_STATE='exact'
      elif [ "$path" = "$GAFFER_HOME" ]; then
        MARKETPLACE_STATE='legacy-v0'
      else
      MARKETPLACE_STATE='conflict'
      fi
      MARKETPLACE_SOURCE="$source"
      MARKETPLACE_PATH="$path"
      ;;
    *)
      die "Claude reports $MARKETPLACE_COUNT Gaffer marketplace records; expected at most one"
      ;;
  esac
}

ensure_marketplace_source() {
  local marketplace_list

  marketplace_list="$(run_bounded_cli \
    "$LIST_TIMEOUT_SECONDS" "$CLAUDE_BIN" plugin marketplace list --json)" ||
    die "Claude marketplace list failed"
  read_marketplace_state "$marketplace_list"
  case "$MARKETPLACE_STATE" in
    exact)
      return 0
      ;;
    absent|legacy-v0)
      run_bounded_cli "$MUTATION_TIMEOUT_SECONDS" \
        "$CLAUDE_BIN" plugin marketplace add "$GAFFER_SOURCE" --scope user ||
        die "Claude Gaffer marketplace registration failed"
      ;;
    conflict)
      die "Claude Gaffer marketplace conflicts with the managed source: ${MARKETPLACE_SOURCE:-unknown}:${MARKETPLACE_PATH:-unknown}"
      ;;
  esac

  marketplace_list="$(run_bounded_cli \
    "$LIST_TIMEOUT_SECONDS" "$CLAUDE_BIN" plugin marketplace list --json)" ||
    die "Claude marketplace list failed after Gaffer registration"
  read_marketplace_state "$marketplace_list"
  [ "$MARKETPLACE_STATE" = exact ] ||
    die "Claude did not register the exact managed Gaffer marketplace"
}

version_matches() {
  local version="$1" revision="$2" resolved

  [[ "$version" =~ ^[0-9a-f]{12}$|^[0-9a-f]{40}$ ]] || return 1
  resolved="$("$GIT_BIN" -C "$GAFFER_HOME" rev-parse --verify "$version^{commit}" 2>/dev/null)" ||
    return 1
  [ "$resolved" = "$revision" ]
}

if [ "${1:-}" = "$BOUNDED_CHILD_MODE" ]; then
  shift
  bounded_child_main "$@"
  exit 125
fi

require_exact_revision
acquire_sync_lock
materialize_managed_source
[ -f "$GAFFER_SOURCE/.claude-plugin/marketplace.json" ] &&
  [ -f "$GAFFER_SOURCE/.claude-plugin/plugin.json" ] ||
  die "Gaffer Claude plugin source is missing under $GAFFER_SOURCE"
require_commit_version_contract
ensure_marketplace_source

plugin_list="$(run_bounded_cli \
  "$LIST_TIMEOUT_SECONDS" "$CLAUDE_BIN" plugin list --json)" ||
  die "Claude plugin list failed"
read_plugin_state "$plugin_list"

if [ "$PLUGIN_COUNT" = 1 ] && version_matches "$PLUGIN_VERSION" "$GAFFER_REV"; then
  exit 0
fi

if [ "$PLUGIN_COUNT" = 1 ]; then
  run_bounded_cli "$MUTATION_TIMEOUT_SECONDS" \
    "$CLAUDE_BIN" plugin update "$PLUGIN_ID" --scope user ||
    die "Claude Gaffer plugin update failed"
else
  run_bounded_cli "$MUTATION_TIMEOUT_SECONDS" \
    "$CLAUDE_BIN" plugin install "$PLUGIN_ID" --scope user ||
    die "Claude Gaffer plugin install failed"
fi

materialize_managed_source
plugin_list="$(run_bounded_cli \
  "$LIST_TIMEOUT_SECONDS" "$CLAUDE_BIN" plugin list --json)" ||
  die "Claude plugin list failed after Gaffer reconciliation"
read_plugin_state "$plugin_list"
[ "$PLUGIN_COUNT" = 1 ] ||
  die "Claude did not report Gaffer installed after reconciliation"
version_matches "$PLUGIN_VERSION" "$GAFFER_REV" ||
  die "Claude Gaffer version is $PLUGIN_VERSION, expected ${GAFFER_REV:0:12}"
materialize_managed_source
