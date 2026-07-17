#!/usr/bin/env bash
set -uo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
GIT_BIN="${GIT_BIN:-git}"
JQ_BIN="${JQ_BIN:-jq}"
TIMEOUT_BIN="${TIMEOUT_BIN:-timeout}"
GAFFER_HOME="${GAFFER_HOME:-$HOME/code/gaffer}"
PLUGIN_ID="gaffer@gaffer"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

read_head() {
  "$GIT_BIN" -C "$GAFFER_HOME" rev-parse --verify HEAD 2>/dev/null ||
    die "Gaffer source HEAD could not be resolved"
}

require_copyable_source() {
  local expected_head="$1" branch dirty head
  branch="$("$GIT_BIN" -C "$GAFFER_HOME" symbolic-ref --quiet --short HEAD 2>/dev/null)" ||
    die "Gaffer source must be on the main branch"
  [ "$branch" = main ] || die "Gaffer source is on '$branch', expected 'main'"
  dirty="$("$GIT_BIN" -C "$GAFFER_HOME" status --porcelain --untracked-files=normal 2>/dev/null)" ||
    die "Gaffer source status could not be read"
  [ -z "$dirty" ] || die "Gaffer source is dirty; commit or remove every tracked/untracked change before rebuild"
  head="$(read_head)" || exit
  [ "$head" = "$expected_head" ] ||
    die "Gaffer source changed while Claude was reconciling its cache"
}

require_commit_version_contract() {
  "$JQ_BIN" -e 'has("version") | not' \
    "$GAFFER_HOME/.claude-plugin/plugin.json" >/dev/null ||
    die "Gaffer plugin.json must omit version so Claude resolves the Git commit"
  "$JQ_BIN" -e '
    [.plugins[] | select(.name == "gaffer")] as $matches
    | ($matches | length) == 1
      and ($matches[0] | has("version") | not)
  ' "$GAFFER_HOME/.claude-plugin/marketplace.json" >/dev/null ||
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

version_matches() {
  local version="$1" head="$2"
  [ "$version" = "$head" ] || [ "$version" = "${head:0:12}" ]
}

INITIAL_HEAD="$(read_head)" || exit
plugin_list="$("$TIMEOUT_BIN" 10 "$CLAUDE_BIN" plugin list --json)" ||
  die "Claude plugin list failed"
read_plugin_state "$plugin_list"

if [ "$PLUGIN_COUNT" = 1 ] && version_matches "$PLUGIN_VERSION" "$INITIAL_HEAD"; then
  exit 0
fi

[ -f "$GAFFER_HOME/.claude-plugin/marketplace.json" ] &&
  [ -f "$GAFFER_HOME/.claude-plugin/plugin.json" ] ||
  die "Gaffer Claude plugin source is missing under $GAFFER_HOME"
require_copyable_source "$INITIAL_HEAD"
require_commit_version_contract

if [ "$PLUGIN_COUNT" = 1 ]; then
  "$TIMEOUT_BIN" 30 "$CLAUDE_BIN" plugin update "$PLUGIN_ID" --scope user ||
    die "Claude Gaffer plugin update failed"
else
  "$TIMEOUT_BIN" 10 "$CLAUDE_BIN" plugin marketplace add "$GAFFER_HOME" --scope user \
    >/dev/null 2>&1 || true
  "$TIMEOUT_BIN" 30 "$CLAUDE_BIN" plugin install "$PLUGIN_ID" --scope user ||
    die "Claude Gaffer plugin install failed"
fi

require_copyable_source "$INITIAL_HEAD"
plugin_list="$("$TIMEOUT_BIN" 10 "$CLAUDE_BIN" plugin list --json)" ||
  die "Claude plugin list failed after Gaffer reconciliation"
read_plugin_state "$plugin_list"
[ "$PLUGIN_COUNT" = 1 ] ||
  die "Claude did not report Gaffer installed after reconciliation"
version_matches "$PLUGIN_VERSION" "$INITIAL_HEAD" ||
  die "Claude Gaffer version is $PLUGIN_VERSION, expected ${INITIAL_HEAD:0:12}"
require_copyable_source "$INITIAL_HEAD"
