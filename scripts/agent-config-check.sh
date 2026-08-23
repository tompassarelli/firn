#!/usr/bin/env bash
# Provider-neutral anti-rot check for the shared agent harness and its adapters.
# Default output is intentionally a small status report. Use --verbose for the
# individual assertions; failures always print their full diagnostic.
set -uo pipefail

AGENT_CONFIG_CHECK_SELF="${BASH_SOURCE[0]}"
AGENT_CONFIG_BOUNDED_CHILD_MODE='--agent-config-bounded-child-v1'

is_positive_probe_decimal() {
  local value="$1"

  [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
    [ -n "${value//[0.]/}" ]
}

hold_probe_group() {
  trap '' TERM
  while :; do
    "${PROBE_SLEEP_BIN:-sleep}" 3600 || true
  done
}

probe_child_main() {
  local pid_file="$1" status_file="$2" stdout_file="$3" stderr_file="$4"
  local command_pid command_status term_observed=0 temp
  shift 4
  [ "$#" -gt 0 ] || exit 125

  temp="$(mktemp "${pid_file}.tmp.XXXXXX")" || exit 125
  printf '%s\n' "$$" >"$temp" || exit 125
  command mv "$temp" "$pid_file" || exit 125
  trap 'term_observed=1' TERM
  (
    ulimit -f "${PROBE_MAX_OUTPUT_KIB:-256}" || exit 125
    exec "$@"
  ) >"$stdout_file" 2>"$stderr_file" &
  command_pid=$!
  wait "$command_pid" 2>>"$stderr_file"
  command_status=$?
  if [ "$term_observed" -eq 1 ]; then
    hold_probe_group
  fi

  temp="$(mktemp "${status_file}.tmp.XXXXXX")" || exit 125
  printf '%s\n' "$command_status" >"$temp" || exit 125
  command mv "$temp" "$status_file" || exit 125
  hold_probe_group
}

run_bounded_process() {
  local duration="$1" scratch pid_file status_file stdout_file stderr_file
  local timeout_pid timeout_status timeout_pgid leader leader_pgid command_status
  local stdout_size stderr_size max_output_bytes
  shift

  if ! is_positive_probe_decimal "$duration" ||
     ! is_positive_probe_decimal "${PROBE_KILL_AFTER_SECONDS:-2}" ||
     ! is_positive_probe_decimal "${PROBE_POLL_SECONDS:-0.02}" ||
     ! [[ "${PROBE_MAX_OUTPUT_KIB:-256}" =~ ^[1-9][0-9]*$ ]]; then
    printf 'invalid bounded-probe limit\n' >&2
    return 125
  fi
  max_output_bytes=$((${PROBE_MAX_OUTPUT_KIB:-256} * 1024))
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/agent-probe.XXXXXX")" || return 125
  pid_file="$scratch/leader"
  status_file="$scratch/status"
  stdout_file="$scratch/stdout"
  stderr_file="$scratch/stderr"

  "${PROBE_TIMEOUT_BIN:-timeout}" --signal=TERM \
    --kill-after="${PROBE_KILL_AFTER_SECONDS:-2}" "$duration" \
    "$AGENT_CONFIG_CHECK_SELF" "$AGENT_CONFIG_BOUNDED_CHILD_MODE" \
    "$pid_file" "$status_file" "$stdout_file" "$stderr_file" "$@" &
  timeout_pid=$!
  while [ ! -s "$status_file" ] && kill -0 "$timeout_pid" 2>/dev/null; do
    "${PROBE_SLEEP_BIN:-sleep}" "${PROBE_POLL_SECONDS:-0.02}"
  done

  if [ -s "$status_file" ]; then
    IFS= read -r leader <"$pid_file" || leader=''
    IFS= read -r command_status <"$status_file" || command_status=''
    timeout_pgid="$("${PROBE_PS_BIN:-ps}" -o pgid= -p "$timeout_pid" 2>/dev/null || true)"
    leader_pgid="$("${PROBE_PS_BIN:-ps}" -o pgid= -p "$leader" 2>/dev/null || true)"
    timeout_pgid="${timeout_pgid//[[:space:]]/}"
    leader_pgid="${leader_pgid//[[:space:]]/}"
    if [[ "$leader" =~ ^[1-9][0-9]*$ ]] &&
       [[ "$command_status" =~ ^[0-9]+$ ]] &&
       [ "$command_status" -le 255 ] &&
       [ "$timeout_pgid" = "$timeout_pid" ] &&
       [ "$leader_pgid" = "$timeout_pid" ]; then
      kill -KILL -- "-$timeout_pid" 2>/dev/null || true
      wait "$timeout_pid" 2>/dev/null || true
      stdout_size="$("${PROBE_WC_BIN:-wc}" -c <"$stdout_file" 2>/dev/null || printf invalid)"
      stderr_size="$("${PROBE_WC_BIN:-wc}" -c <"$stderr_file" 2>/dev/null || printf invalid)"
      if
       [[ "$stdout_size" =~ ^[0-9]+$ ]] &&
       [[ "$stderr_size" =~ ^[0-9]+$ ]] &&
       [ "$stdout_size" -lt "$max_output_bytes" ] &&
       [ "$stderr_size" -lt "$max_output_bytes" ]
      then
        [ ! -s "$stderr_file" ] || command cat "$stderr_file" >&2
        [ ! -f "$stdout_file" ] || command cat "$stdout_file"
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

 run_codex_probe() {
  local duration="$1"
  shift
  run_bounded_process "$duration" "${CODEX_BIN:-codex}" "$@"
}

run_codex_mcp_inventory() {
  local duration="$1"

  run_codex_probe "$duration" \
    -c 'mcp_servers.linear-mcp-msa-new.enabled=false' \
    mcp list --json
}

codex_mcp_inventory_server_has_state() {
  local inventory="$1" server="$2" expected_enabled="$3"

  jq -e \
    --arg server "$server" \
    --argjson expected_enabled "$expected_enabled" \
    '
      if type != "array" then false
      else
        [.[] | select(.name? == $server)] as $matches
        | ($matches | length) == 1
          and $matches[0].enabled? == $expected_enabled
      end
    ' <<<"$inventory" >/dev/null
}

orchestration_version_matches() {
  local version="$1" commit="$2"

  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ "$version" =~ ^[0-9a-f]{12}$|^[0-9a-f]{40}$ ]] || return 1
  [ "$version" = "$commit" ] || [ "$version" = "${commit:0:12}" ]
}

orchestration_revisions_converged() {
  local intent="$1" source_head="$2" verified_input="$3"

  [[ "$intent" =~ ^[0-9a-f]{40}$ ]] &&
    [ "$intent" = "$source_head" ] &&
    [ "$intent" = "$verified_input" ]
}

north_provider_schema_version() {
  jq -er '
    .schemaVersion as $version
    | if (($version | type) == "number"
          and ($version | floor) == $version
          and $version >= 1)
      then $version | tostring
      else error("invalid provider schemaVersion")
      end
  '
}

run_north_packaged() {
  run_bounded_process "${NORTH_PROBE_TIMEOUT_SECONDS:-15}" \
    "${NORTH_PACKAGED_BIN:-north-packaged}" "$@"
}

codex_north_env_is_canonical() {
  python3 - "$1" <<'PY'
import json
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)

expected = {
    "BEAGLE_STORE_LOG": "/home/tom/.local/state/north/coordination.log",
    "BEAGLE_STORE_TELEMETRY_LOG": "/home/tom/.local/state/north/telemetry.log",
    "BEAGLE_STORE_THREADS": "/home/tom/.local/state/north/threads",
    "NORTH_PORT": "7977",
}
actual = config.get("mcp_servers", {}).get("north", {}).get("env")
if actual != expected:
    print(
        "expected "
        + json.dumps(expected, sort_keys=True)
        + ", observed "
        + json.dumps(actual, sort_keys=True),
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

codex_mcp_commands_are_immutable() {
  python3 - "$1" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)

expected = {
    "north": "/run/current-system/sw/bin/north-mcp",
}
servers = config.get("mcp_servers", {})
for name, command in expected.items():
    actual = servers.get(name, {}).get("command")
    if actual != command:
        print(f"{name}: expected {command}, observed {actual!r}", file=sys.stderr)
        raise SystemExit(1)
PY
}

declare -A LIVE_HOOK_TARGET_BY_ROLE=()
declare -A LIVE_HOOK_HASH_BY_ROLE=()

hook_target_fingerprint() {
  local declared="$1" resolved hash canonical_root allowed=0
  shift

  [ -x "$declared" ] || return 1
  resolved="$(readlink -f "$declared" 2>/dev/null)" || return 1
  for canonical_root in "$@"; do
    case "$resolved" in
      "$canonical_root"/*) allowed=1; break ;;
    esac
  done
  [ "$allowed" -eq 1 ] || return 1
  hash="$(sha256sum "$resolved" 2>/dev/null | awk '{print $1}')" || return 1
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\t%s\n' "$resolved" "$hash"
}

record_live_hook_binding() {
  local role="$1" target="$2" hash="$3"

  HOOK_SPLIT_REASON=''
  if [[ -v "LIVE_HOOK_TARGET_BY_ROLE[$role]" ]] &&
     { [ "${LIVE_HOOK_TARGET_BY_ROLE[$role]}" != "$target" ] ||
       [ "${LIVE_HOOK_HASH_BY_ROLE[$role]}" != "$hash" ]; }; then
    HOOK_SPLIT_REASON="$role changed from ${LIVE_HOOK_TARGET_BY_ROLE[$role]}@${LIVE_HOOK_HASH_BY_ROLE[$role]} to $target@$hash"
    return 1
  fi
  LIVE_HOOK_TARGET_BY_ROLE["$role"]="$target"
  LIVE_HOOK_HASH_BY_ROLE["$role"]="$hash"
}

canonical_existing_path() {
  local path="$1"
  [ -e "$path" ] || return 1
  readlink -f -- "$path" 2>/dev/null
}

managed_source_root_matches() {
  local logical_source="$1" observed_root="$2"
  local expected_canonical observed_canonical
  expected_canonical="$(canonical_existing_path "$logical_source")" || return 1
  observed_canonical="$(canonical_existing_path "$observed_root")" || return 1
  [ "$observed_canonical" = "$expected_canonical" ]
}

codex_managed_policy_binding_count() {
  python3 - "$1" <<'PY'
import sys
import tomllib

def command(path, timeout):
    interpreter = "node" if path.endswith(".js") else "bash"
    return {
        "type": "command",
        "command": (
            "/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV "
            "/etc/codex/hooks/runtime/%s /etc/codex/hooks/%s"
            % (interpreter, path)
        ),
        "timeout": timeout,
    }

def direct_command(path, timeout):
    return {"type": "command", "command": path, "timeout": timeout}

enabled = {
    "allow_managed_hooks_only": True,
    "allow_remote_control": False,
    "managed_hook_failure_mode": "block",
    "features": {"hooks": True},
    "hooks": {
        "managed_dir": "/etc/codex/hooks",
        "SessionStart": [{
            "hooks": [
                command("beagle-session-start.sh", 30),
                command("north-on-spawn-codex", 15),
            ],
        }],
        "SubagentStart": [{
            "hooks": [command("north-on-spawn-codex", 15)],
        }],
        "SessionEnd": [{
            "hooks": [command("north-on-terminal-codex", 3)],
        }],
        "SubagentStop": [{
            "hooks": [command("north-on-terminal-codex", 3)],
        }],
        "PreToolUse": [
            {
                "matcher": "^(Agent|Task|Workflow)$",
                "hooks": [command("agent-spawn-guard.sh", 10)],
            },
            {
                "matcher": "^(Edit|Write|MultiEdit|apply_patch)$",
                "hooks": [
                    command("launch-critical-worktree-guard.sh", 10),
                ],
            },
            {
                "matcher": "^(Edit|Write|MultiEdit)$",
                "hooks": [
                    direct_command("/run/current-system/sw/bin/firn-system-policy", 10),
                ],
            },
            {
                "matcher": "^Bash$",
                "hooks": [
                    command("agent-spawn-guard.sh", 10),
                    command("tripwire-guard.sh", 10),
                    direct_command("/run/current-system/sw/bin/firn-system-policy", 10),
                    command("launch-critical-worktree-guard.sh", 10),
                    command("corpus-scan-guard.sh", 10),
                    command("session-kill-guard.sh", 10),
                ],
            },
        ],
        "PostToolUse": [
            {
                "matcher": "^Bash$",
                "hooks": [
                    command("logcompress-hook.js", 10),
                    command("north-on-tooluse-codex", 10),
                ],
            },
            {
                "matcher": "^(Edit|Write|MultiEdit|apply_patch)$",
                "hooks": [command("north-on-tooluse-codex", 10)],
            },
            {
                "matcher": "^(mcp__north__spawn|mcp__north__dispatch|Task|Agent)$",
                "hooks": [command("north-mark-delegated-codex", 10)],
            },
        ],
        "Stop": [{
            "hooks": [command("north-on-stop-codex", 10)],
        }],
    },
}

disabled = {
    "allow_managed_hooks_only": True,
    "allow_remote_control": False,
    "features": {"hooks": False},
}

with open(sys.argv[1], "rb") as handle:
    policy = tomllib.load(handle)
if type(policy.get("allow_managed_hooks_only")) is not bool:
    raise SystemExit("allow_managed_hooks_only must be a boolean")
if type(policy.get("allow_remote_control")) is not bool:
    raise SystemExit("allow_remote_control must be a boolean")
if policy == disabled:
    print(0)
elif policy == enabled:
    print(sum(
        len(binding["hooks"])
        for event, bindings in policy["hooks"].items()
        if event != "managed_dir"
        for binding in bindings
    ))
else:
    raise SystemExit("managed Codex policy differs from an authoritative enabled or disabled contract")
PY
}

canonical_link() {
  local link="$1" expected="$2" label="$3"
  local got want
  got="$(readlink -f "$link" 2>/dev/null || true)"
  want="$(readlink -f "$expected" 2>/dev/null || true)"
  if [ -n "$got" ] && [ "$got" = "$want" ]; then ok_detail "$label → ${want#"$REPO"/}"
  else bad "$label resolves to '${got:-missing}', expected '$want'"; fi
}

immutable_store_link_matches() {
  local link="$1" expected="$2" label="$3" resolved
  local store_prefix="${NIX_STORE_PREFIX:-/nix/store}"

  if [ ! -L "$link" ]; then
    bad "$label must be a generation-owned symlink"
    return 1
  fi
  resolved="$(readlink -f "$link" 2>/dev/null || true)"
  case "$resolved" in
    "$store_prefix"/*) ;;
    *)
      bad "$label resolves outside $store_prefix: ${resolved:-missing}"
      return 1
      ;;
  esac
  if cmp -s "$resolved" "$expected"; then
    ok_detail "$label is an exact generation-owned store copy"
  else
    bad "$label differs from the committed generation source"
    return 1
  fi
}

locked_git_blob_matches_file() {
  local live="$1" source_repo="$2" revision="$3" relative="$4"

  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  git -C "$source_repo" cat-file -e "$revision:$relative" 2>/dev/null ||
    return 1
  [ -f "$live" ] || return 1
  cmp -s "$live" <(git -C "$source_repo" show "$revision:$relative")
}

managed_hook_source_matches() {
  local live="$1" expected_checkout="$2" authority="$3"
  local source_repo="$4" revision="$5" git_blob_path="$6"

  case "$authority" in
    self) cmp -s "$live" "$expected_checkout" ;;
    north|beagle)
      locked_git_blob_matches_file \
        "$live" "$source_repo" "$revision" "$git_blob_path"
      ;;
    *) return 1 ;;
  esac
}

# North and Beagle enforcement is published by north-enforcement-promote, not by
# the flake pin, so its attested revision comes from the active promote record.
NORTH_ENFORCEMENT_ROOT="${NORTH_ENFORCEMENT_STATE_ROOT:-/var/lib/north-enforcement}"

promote_record_path() {
  printf '%s' "$NORTH_ENFORCEMENT_ROOT/active/record"
}

promote_record_revision() {
  local node="$1" field value
  case "$node" in
    north) field=NORTH_REV ;;
    beagle) field=BEAGLE_REV ;;
    *) return 1 ;;
  esac
  value="$(sed -n "s/^$field //p" "$(promote_record_path)" 2>/dev/null | head -n 1)"
  [[ "$value" =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s' "$value"
}

# The promoted replacement for store residency. A store path is immutable because
# the store is; a promoted path has to prove the same thing about itself: it
# resolves inside the active deployment, is root-owned and read-only, carries no
# second hard link (which would be a writable back door into a sealed tree), and
# hashes to what the promote record attested.
sealed_promoted_file() {
  local live="$1" relative="$2"
  local resolved expected deployments observed recorded digest

  resolved="$(readlink -f "$live" 2>/dev/null || true)"
  expected="$(
    readlink -f "$NORTH_ENFORCEMENT_ROOT/active/current/$relative" 2>/dev/null || true
  )"
  [ -n "$resolved" ] && [ "$resolved" = "$expected" ] || return 1
  deployments="$(readlink -f "$NORTH_ENFORCEMENT_ROOT/deployments" 2>/dev/null || true)"
  [ -n "$deployments" ] && [[ "$resolved" = "$deployments"/* ]] || return 1
  [ -f "$resolved" ] && [ ! -L "$resolved" ] || return 1
  observed="$(stat -c '%u:%a:%h' "$resolved" 2>/dev/null)" || return 1
  [ "$observed" = '0:444:1' ] || return 1
  recorded="$(
    awk -v want="$relative" '$1 == "FILE" && $3 == want { print $2; exit }' \
      "$(promote_record_path)" 2>/dev/null
  )"
  [[ "$recorded" =~ ^[0-9a-f]{64}$ ]] || return 1
  digest="$(sha256sum <"$resolved" 2>/dev/null | cut -d' ' -f1)"
  [ "$digest" = "$recorded" ]
}

write_shell_script_bin_matches_source() {
  local live="$1" source="$2" store_root="${3:-/nix/store}"
  local resolved canonical_store package_root interpreter interpreter_package first_line

  [ -f "$source" ] || return 1
  resolved="$(realpath -e "$live" 2>/dev/null)" || return 1
  canonical_store="$(realpath -e "$store_root" 2>/dev/null)" || return 1
  package_root="$(dirname "$(dirname "$resolved")")"
  [ "$(dirname "$package_root")" = "$canonical_store" ] || return 1
  [[ "${package_root##*/}" =~ ^[a-z0-9]{32}-north-session-end$ ]] || return 1
  [ "$resolved" = "$package_root/bin/north-session-end" ] &&
    [ -f "$resolved" ] && [ ! -L "$resolved" ] && [ -x "$resolved" ] || return 1

  IFS= read -r first_line <"$resolved" || return 1
  [[ "$first_line" = '#!'* ]] || return 1
  interpreter="${first_line#\#!}"
  [ -n "$interpreter" ] && [ "$first_line" = "#!$interpreter" ] || return 1
  case "$interpreter" in
    "$canonical_store"/*/bin/bash) ;;
    *) return 1 ;;
  esac
  interpreter_package="${interpreter%/bin/bash}"
  [ "$(dirname "$interpreter_package")" = "$canonical_store" ] &&
    [[ "${interpreter_package##*/}" =~ ^[a-z0-9]{32}-bash[^/]*$ ]] || return 1
  [ -x "$interpreter" ] || return 1

  cmp -s \
    <(tail -n +2 "$resolved") \
    <({ command cat "$source"; printf '\n'; })
}

north_wrapped_runtime_matches_locked_source() {
  local public="$1" source_repo="$2" revision="$3" relative="$4"
  local store_root="${5:-/nix/store}"
  local resolved canonical_store package_root wrapped wrapper_interpreter interpreter_package
  local wrapper_header body_header locked_body locked_header expected_home expected_exec
  local path_line path_entry path_package index=1 path_blocks=0
  local -a wrapper_lines=()

  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  git -C "$source_repo" cat-file -e "$revision:$relative" 2>/dev/null || return 1
  resolved="$(realpath -e "$public" 2>/dev/null)" || return 1
  canonical_store="$(realpath -e "$store_root" 2>/dev/null)" || return 1
  [[ "$resolved" = */"$relative" ]] || return 1
  package_root="${resolved%/"$relative"}"
  [ "$(dirname "$package_root")" = "$canonical_store" ] || return 1
  [[ "${package_root##*/}" =~ ^[a-z0-9]{32}-north[^/]*$ ]] || return 1
  [ "$resolved" = "$package_root/$relative" ] &&
    [ -f "$resolved" ] && [ ! -L "$resolved" ] && [ -x "$resolved" ] || return 1

  wrapped="$package_root/${relative%/*}/.${relative##*/}-wrapped"
  [ -f "$wrapped" ] && [ ! -L "$wrapped" ] && [ -x "$wrapped" ] || return 1
  IFS= read -r wrapper_header <"$resolved" || return 1
  [[ "$wrapper_header" = '#! '*' -e' ]] || return 1
  wrapper_interpreter="${wrapper_header#\#! }"
  wrapper_interpreter="${wrapper_interpreter% -e}"
  case "$wrapper_interpreter" in
    "$canonical_store"/*/bin/bash) ;;
    *) return 1 ;;
  esac
  interpreter_package="${wrapper_interpreter%/bin/bash}"
  [ "$(dirname "$interpreter_package")" = "$canonical_store" ] &&
    [[ "${interpreter_package##*/}" =~ ^[a-z0-9]{32}-bash[^/]*$ ]] || return 1
  [ -x "$wrapper_interpreter" ] || return 1

  IFS= read -r body_header <"$wrapped" || return 1
  [ "$body_header" = "#!$wrapper_interpreter" ] || return 1
  # Slice the shebang in-shell: `| head -n 1` under pipefail reports SIGPIPE
  # (141) and would flag a byte-perfect wrapper as provenance drift.
  locked_body="$(git -C "$source_repo" show "$revision:$relative")" || return 1
  locked_header="${locked_body%%$'\n'*}"
  [[ "$locked_header" = '#!'* ]] || return 1
  cmp -s \
    <(tail -n +2 "$wrapped") \
    <(git -C "$source_repo" show "$revision:$relative" | tail -n +2) || return 1

  expected_home="export NORTH_HOME='$package_root'"
  expected_exec='exec -a "$0" "'"$wrapped"'"  "$@" '
  mapfile -t wrapper_lines <"$resolved"
  [ "${wrapper_lines[0]:-}" = "$wrapper_header" ] || return 1
  while [ "$index" -lt "${#wrapper_lines[@]}" ] &&
        [ "${wrapper_lines[$index]}" = "PATH=\${PATH:+':'\$PATH':'}" ]; do
    [ $((index + 5)) -lt "${#wrapper_lines[@]}" ] || return 1
    path_line="${wrapper_lines[$((index + 2))]}"
    [ "${#path_line}" -gt 12 ] &&
      [ "${path_line:0:6}" = "PATH='" ] &&
      [ "${path_line: -6}" = "'\$PATH" ] || return 1
    path_entry="${path_line:6:${#path_line}-12}"
    case "$path_entry" in
      "$canonical_store"/*/bin) ;;
      *) return 1 ;;
    esac
    path_package="${path_entry%/bin}"
    [ "$(dirname "$path_package")" = "$canonical_store" ] &&
      [[ "${path_package##*/}" =~ ^[a-z0-9]{32}-[^/]+$ ]] &&
      [ -d "$path_entry" ] || return 1
    [ "${wrapper_lines[$((index + 1))]}" = "PATH=\${PATH/':''${path_entry}'':'/':'}" ] &&
      [ "${wrapper_lines[$((index + 3))]}" = "PATH=\${PATH#':'}" ] &&
      [ "${wrapper_lines[$((index + 4))]}" = "PATH=\${PATH%':'}" ] &&
      [ "${wrapper_lines[$((index + 5))]}" = 'export PATH' ] || return 1
    path_blocks=$((path_blocks + 1))
    index=$((index + 6))
  done
  [ "$path_blocks" -gt 0 ] || return 1
  [ "$index" -eq $((${#wrapper_lines[@]} - 2)) ] &&
    [ "${wrapper_lines[$index]}" = "$expected_home" ] &&
    [ "${wrapper_lines[$((index + 1))]}" = "$expected_exec" ]
}

# Read one decision from North's immutable activation generation. This checker
# does not resolve permissions, sets, claims, or kill switches independently.
north_unit_activity_state() {
  local wanted_kind="$1" wanted_name="$2"
  local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  local state_root="${NORTH_AGENT_STATE_ROOT:-$state_home/north/agents}"
  local activation_file="${AGENT_CONFIG_ACTIVATION_FILE:-$state_root/current/activation.json}"

  if [ ! -r "$activation_file" ]; then
    printf 'unknown\n'
    return 0
  fi
  jq -er --arg kind "$wanted_kind" --arg id "$wanted_name" '
    if .schema != "north.agent-activation/v1"
       or ((.catalogDigest | type) != "string")
       or ((.catalogDigest | test("^sha256:[0-9a-f]{64}$")) | not)
       or ((.generationId | type) != "string")
       or ((.generationId | test("^sha256:[0-9a-f]{64}$")) | not)
       or (.units | type) != "array"
    then "invalid"
    else [.units[] | select(.kind == $kind and .id == $id)] as $matches
      | if ($matches | length) != 1 then "off"
        elif (($matches[0].permission | type) != "string")
             or (($matches[0].permission | test("^(on|off|off:until=)")) | not)
             or (($matches[0].active | type) != "boolean") then "invalid"
        elif $matches[0].active == true then "on"
        else "off"
        end
    end
  ' "$activation_file" 2>/dev/null || printf 'invalid\n'
}

north_unit_activity_is_active() {
  case "$(north_unit_activity_state "$1" "$2")" in
    on) return 0 ;;
    *) return 1 ;;
  esac
}

run_agent_policy_contract() {
  local repo="$1" local_mode="${2:-0}"
  local -a args=(--repo "$repo")
  [ "$local_mode" -eq 0 ] || args+=(--local)
  python3 "$repo/scripts/agent-policy-contract.py" "${args[@]}"
}

if [ "${1:-}" = "$AGENT_CONFIG_BOUNDED_CHILD_MODE" ]; then
  shift
  probe_child_main "$@"
  exit 125
fi

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="${AGENT_CONFIG_NORTH_PROFILE:-$HOME/code/north/main/profiles/tom}"
BEAGLE_INTEGRATION="${AGENT_CONFIG_BEAGLE_INTEGRATION:-$HOME/code/beagle/main/integrations/north}"
FIRN_INTEGRATION="$REPO/modules/north-profile/firn"
CODEX="$REPO/dotfiles/codex"
LIVE_REPO="${AGENT_CONFIG_LIVE_REPO:-$HOME/code/nixos-config}"
LIVE_SHARED="${AGENT_CONFIG_LIVE_NORTH_PROFILE:-$HOME/code/north/main/profiles/tom}"
LIVE_AGENT_ROOT="${NORTH_AGENT_STATE_ROOT:-$HOME/.local/state/north/agents}"
LIVE_SKILLS_FARM="${AGENT_CONFIG_LIVE_SKILLS_FARM:-$LIVE_AGENT_ROOT/current/skills/shared}"
LIVE_NORTH_ROOT="${AGENT_CONFIG_LIVE_NORTH_ROOT:-$HOME/code/north}"
LIVE_BEAGLE_ROOT="${AGENT_CONFIG_LIVE_BEAGLE_ROOT:-$HOME/code/beagle}"
LIVE_FIRN_ROOT="${AGENT_CONFIG_LIVE_FIRN_ROOT:-$HOME/code/nixos-config}"
CODEX_REQUIREMENTS="$REPO/modules/codex/requirements.toml"
LAUNCHER_BIN="$REPO/dotfiles/bin"
LOCAL=0
VERBOSE=0
POLICY_ONLY=0
# This repository declares Tom's machine profile; CI's HOME is runner scratch.
CANONICAL_PROFILE_HOME=/home/tom
CANONICAL_BEAGLE_STORE_LOG="$CANONICAL_PROFILE_HOME/.local/state/north/coordination.log"
CANONICAL_BEAGLE_STORE_TELEMETRY_LOG="$CANONICAL_PROFILE_HOME/.local/state/north/telemetry.log"
CANONICAL_BEAGLE_STORE_THREADS="$CANONICAL_PROFILE_HOME/.local/state/north/threads"
# MCP servers whose live-connection health is advisory-only, not FAIL-worthy.
for arg in "$@"; do
  case "$arg" in
    --local) LOCAL=1 ;;
    --policy-only) POLICY_ONLY=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    *) printf 'usage: %s [--local] [--policy-only] [--verbose]\n' "$0" >&2; exit 2 ;;
  esac
done

if [ "$POLICY_ONLY" -eq 1 ]; then
  run_agent_policy_contract "$REPO" "$LOCAL"
  exit $?
fi

fail=0
warn=0
details=()
ok_detail() { details+=("ok: $*"); }
note() { [ "$VERBOSE" -eq 0 ] || printf '  note: %s\n' "$*"; }
bad() { printf '  FAIL: %s\n' "$*" >&2; fail=$((fail + 1)); }
soft() { printf '  warn: %s\n' "$*" >&2; warn=$((warn + 1)); }
COORDINATION_ACTIVITY="$(north_unit_activity_state set coordination)"
AGENT_SPAWN_GUARD_ACTIVITY="$(north_unit_activity_state hook agent-spawn-guard)"
NORTH_LIFECYCLE_ACTIVITY="$(north_unit_activity_state hook north-session-lifecycle)"
COORDINATION_ACTIVE=0
north_unit_activity_is_active set coordination && COORDINATION_ACTIVE=1
group() {
  local name="$1" summary="$2" before="$3"
  if [ "$fail" -eq "$before" ]; then printf '✓ %-13s %s\n' "$name" "$summary"
  else printf '✗ %-13s %s\n' "$name" "$summary" >&2; fi
  if [ "$VERBOSE" -eq 1 ]; then
    local line
    for line in "${details[@]}"; do printf '  %s\n' "$line"; done
  fi
  details=()
}
provider_group() {
  local name="$1" before="$2"
  shift 2
  if [ "$fail" -eq "$before" ]; then printf '✓ %s\n' "$name"
  else printf '✗ %s\n' "$name" >&2; fi
  local line
  for line in "$@"; do printf '  %s\n' "$line"; done
  if [ "$VERBOSE" -eq 1 ]; then
    for line in "${details[@]}"; do printf '    %s\n' "$line"; done
  fi
  details=()
}
need_json() {
  local file="$1" label="$2"
  if jq -e . "$file" >/dev/null 2>&1; then ok_detail "$label is valid JSON"
  else bad "$label is not valid JSON: $file"; return 1; fi
}
need_toml() {
  local file="$1" label="$2"
  if python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$file" >/dev/null 2>&1; then
    ok_detail "$label is valid TOML"
  else
    bad "$label is not valid TOML: $file"
    return 1
  fi
}
need_yaml() {
  # Strict parse only when a YAML parser is present (PyYAML is not stdlib and
  # is absent from the minimal system python / CI). When absent, structural
  # grep assertions below carry the load — this never hard-fails on a missing
  # parser, only on a genuinely malformed document.
  local file="$1" label="$2"
  [ -f "$file" ] || { bad "$label is missing: $file"; return 1; }
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    if python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$file" >/dev/null 2>&1; then
      ok_detail "$label is valid YAML"
    else
      bad "$label is not valid YAML: $file"
      return 1
    fi
  else
    note "$label YAML strict-parse skipped (no PyYAML); structural checks apply"
  fi
}
printf 'agent harness check%s\n' "$([ "$LOCAL" -eq 1 ] && printf ' (local)' || true)"

before=$fail
if policy_output="$(run_agent_policy_contract "$REPO" "$LOCAL" 2>&1)"; then
  ok_detail "$policy_output"
else
  bad "$policy_output"
fi
group policy 'explicit ownership and exact Firn provider bindings' "$before"

# North-composed constitution plus hook/skill implementations from each owner.
before=$fail
hook_count=0
if command -v shellcheck >/dev/null 2>&1; then
  for hook_root in \
    "$SHARED/hooks" \
    "$BEAGLE_INTEGRATION/hooks" \
    "$FIRN_INTEGRATION/hooks"; do
    if [ ! -d "$hook_root" ]; then
      if [ "$LOCAL" -eq 1 ]; then
        bad "composed hook owner root is missing: $hook_root"
      else
        note "external hook owner root unavailable in repository-only mode: $hook_root"
      fi
      continue
    fi
    while IFS= read -r hook; do
      hook_count=$((hook_count + 1))
      if output="$(shellcheck -S warning "$hook" 2>&1)"; then
        ok_detail "shellcheck ${hook##*/}"
      else bad "shellcheck ${hook##*/}:\n$output"; fi
    done < <(find "$hook_root" -maxdepth 1 -type f -name '*.sh' -print | sort)
  done
else bad "shellcheck is required to lint shared hooks"; fi
skill_count=0
for skill_root in \
  "$REPO/dotfiles/agents/skills" \
  "$SHARED/skills" \
  "$BEAGLE_INTEGRATION/skills" \
  "$FIRN_INTEGRATION/skills"; do
  if [ ! -d "$skill_root" ]; then
    if [ "$LOCAL" -eq 1 ]; then
      bad "composed skill owner root is missing: $skill_root"
    else
      note "external skill owner root unavailable in repository-only mode: $skill_root"
    fi
    continue
  fi
  while IFS= read -r skill; do
    skill_count=$((skill_count + 1))
    if [ "$(head -n 1 "$skill")" = '---' ]; then ok_detail "${skill%/SKILL.md} has frontmatter"
    else soft "${skill#"$REPO"/} lacks SKILL.md frontmatter"; fi
  done < <(find "$skill_root" -mindepth 2 -maxdepth 2 -name SKILL.md -type f -print | sort)
done
if [ -s "$REPO/dotfiles/agents/AGENTS.md" ]; then
  ok_detail "global AGENTS.md owner source present"
else
  bad "global AGENTS.md owner source is missing or empty"
fi
north_profile_module="$REPO/modules/north-profile/default.bnix"
if grep -Fq '"/.local/state/north/agents/current/instructions/shared/AGENTS.md"' "$north_profile_module"; then
  ok_detail "~/.agents/AGENTS.md is wired to North-generation instructions"
else
  bad "~/.agents/AGENTS.md must be wired to the current North activation generation"
fi
for profile_member in docs hooks; do
  if grep -Fq "\"/code/north/main/agent-profile/$profile_member\"" "$north_profile_module"; then
    ok_detail "~/.agents/$profile_member is wired to the North-composed profile"
  else
    bad "~/.agents/$profile_member must be wired to ~/code/north/main/agent-profile"
  fi
done
if grep -Fq '"/.local/state/north/agents/current/skills/shared"' "$north_profile_module"; then
  ok_detail '~/.agents/skills is wired to the current North skills projection'
else
  bad '~/.agents/skills must be wired to the current North activation generation'
fi
if [ "$LOCAL" -eq 1 ]; then
  canonical_link "$HOME/.agents/AGENTS.md" "$LIVE_AGENT_ROOT/current/instructions/shared/AGENTS.md" "$HOME/.agents/AGENTS.md"
  canonical_link "$HOME/.agents/docs" "$LIVE_SHARED/docs" "$HOME/.agents/docs"
  canonical_link "$HOME/.agents/hooks" "$LIVE_SHARED/hooks" "$HOME/.agents/hooks"
  canonical_link "$HOME/.agents/skills" "$LIVE_SKILLS_FARM" "$HOME/.agents/skills"
fi
group shared "$hook_count owner hooks linted · $skill_count owner skills · North-generation instructions" "$before"

validate_codex_managed_policy() {
  if ! need_toml "$CODEX_REQUIREMENTS" 'Codex managed requirements'; then return; fi
  CODEX_MANAGED_BINDINGS="$(
    codex_managed_policy_binding_count "$CODEX_REQUIREMENTS" 2>/dev/null
  )" || CODEX_MANAGED_BINDINGS=''
  if [ "$CODEX_MANAGED_BINDINGS" = 19 ]; then
    ok_detail 'Codex managed-only, fail-closed, remote-control-disabled policy is the exact 19-binding authoritative contract'
  elif [ "$CODEX_MANAGED_BINDINGS" = 0 ]; then
    ok_detail 'Codex managed hooks are authoritatively disabled; remote control remains disabled'
  else
    bad 'Codex managed requirements differ from the authoritative hook contract'
  fi

  local module="$REPO/modules/codex/default.bnix"
  local spec relative source_expr expected_checkout authority git_blob_path
  local promoted_path live resolved adapter expected_adapter
  # relative|module source expression|checkout|authority|blob path|promoted path.
  # A promoted path is the enforcement-deployment-relative name the generation's
  # tmpfiles link points at; it is empty for anything the generation still owns.
  local -a source_specs=(
    "requirements.toml|(s flakeRoot \"/modules/codex/requirements.toml\")|$CODEX_REQUIREMENTS|self|modules/codex/requirements.toml|"
    "lib/north-agent-activation.sh|(s flakeRoot \"/dotfiles/agents/lib/north-agent-activation.sh\")|$REPO/dotfiles/agents/lib/north-agent-activation.sh|self|dotfiles/agents/lib/north-agent-activation.sh|"
    "agent-spawn-guard.sh|(promoted \"agent-spawn-guard.sh\"|$SHARED/hooks/agent-spawn-guard.sh|north|profiles/tom/hooks/agent-spawn-guard.sh|north/profiles/tom/hooks/agent-spawn-guard.sh"
    # launch_critical guard and its Python decision libraries deploy together.
    "launch-critical-worktree-guard.sh|(promoted \"launch-critical-worktree-guard.sh\"|$SHARED/hooks/launch-critical-worktree-guard.sh|north|profiles/tom/hooks/launch-critical-worktree-guard.sh|north/profiles/tom/hooks/launch-critical-worktree-guard.sh"
    "lib/launch_critical_decide.py|(promoted \"lib/launch_critical_decide.py\"|$SHARED/hooks/lib/launch_critical_decide.py|north|profiles/tom/hooks/lib/launch_critical_decide.py|north/profiles/tom/hooks/lib/launch_critical_decide.py"
    "lib/launch_critical_paths.py|(promoted \"lib/launch_critical_paths.py\"|$SHARED/hooks/lib/launch_critical_paths.py|north|profiles/tom/hooks/lib/launch_critical_paths.py|north/profiles/tom/hooks/lib/launch_critical_paths.py"
    "tripwire-guard.sh|(promoted \"tripwire-guard.sh\"|$SHARED/hooks/tripwire-guard.sh|north|profiles/tom/hooks/tripwire-guard.sh|north/profiles/tom/hooks/tripwire-guard.sh"
    "logcompress-hook.js|(promoted \"logcompress-hook.js\"|$SHARED/hooks/logcompress-hook.js|north|profiles/tom/hooks/logcompress-hook.js|north/profiles/tom/hooks/logcompress-hook.js"
    "logcompress.js|(promoted \"logcompress.js\"|$SHARED/hooks/logcompress.js|north|profiles/tom/hooks/logcompress.js|north/profiles/tom/hooks/logcompress.js"
  )
  local -a provider_adapters=(
    north-on-spawn-codex
    north-on-tooluse-codex
    north-mark-delegated-codex
    north-on-stop-codex
    north-on-terminal-codex
    beagle-session-start.sh
    lib/authoring-killswitch.sh
    lib/harness-dial.sh
  )
  for spec in "${source_specs[@]}"; do
    IFS='|' read -r relative source_expr expected_checkout authority \
      git_blob_path promoted_path <<<"$spec"
    if grep -Fq "$source_expr" "$module"; then :
    else bad "Codex module does not install $relative from its owning source: $source_expr"; fi
    if [ -n "$promoted_path" ] &&
       ! grep -Fq "(promoted \"$relative\" \"$promoted_path\")" "$module"; then
      bad "Codex module does not link $relative to the promoted enforcement payload $promoted_path"
    fi
  done
  for adapter in "${provider_adapters[@]}"; do
    if grep -Fq "(providerAdapter \"$adapter\")" "$module"; then :
    else bad "Codex module does not link provider adapter $adapter from the current North generation"; fi
  done
  if grep -Fq '"L+ /etc/codex/hooks/" relative " - - - - " enforcement "/" source' "$module" &&
     grep -Fq 'enforcement "/var/lib/north-enforcement/active/current"' "$module"; then
    ok_detail 'Codex promoted hooks resolve through the active enforcement deployment selector'
  else
    bad 'Codex module must bind promoted hooks to /var/lib/north-enforcement/active/current'
  fi
  local runtime package binary
  local -a runtimes=(
    'bash|pkgs.bash|bash'
    'cat|pkgs.coreutils|cat'
    'env|pkgs.coreutils|env'
    'git|pkgs.git|git'
    'mktemp|pkgs.coreutils|mktemp'
    'node|pkgs.nodejs|node'
    'python3|pkgs.python3|python3'
    'rm|pkgs.coreutils|rm'
    'timeout|pkgs.coreutils|timeout'
  )
  for source in "${runtimes[@]}"; do
    IFS='|' read -r runtime package binary <<<"$source"
    if grep -Fq "\"codex/hooks/runtime/$runtime\"" "$module" &&
       grep -Fq "{:source (s $package \"/bin/$binary\")}" "$module"; then :
    else bad "Codex module does not bind exact runtime $runtime from $package"; fi
  done
  if grep -Fq 'northPkg (s homeDir "/code/north/main")' "$module" &&
     grep -Fq '"codex/hooks/north"' "$module" &&
     grep -Fq '{:source northPkg}' "$module"; then
    ok_detail 'Codex module exposes the complete North hook runtime from the live checkout'
  else
    bad 'Codex module must expose the complete North hook runtime from the live checkout'
  fi
  if grep -Fq 'codexUpstreamPkg pkgs.master.codex' "$module" &&
     grep -Fq ':environment.systemPackages [codexPkg]' "$module" &&
     grep -Fq '"codex/runtime"' "$module" &&
     grep -Fq '{:source codexPkg}' "$module"; then
    ok_detail 'Firn installs the identity-pinned nixpkgs Codex and exposes that exact derivation as the runtime marker'
  else
    bad 'Codex module must install and expose the identity-pinned nixpkgs Codex derivation'
  fi
  if grep -Fq ':mode ' "$module"; then
    bad 'Codex hook sources must remain /etc symlinks into /nix/store; explicit mode copies are forbidden'
  fi

  local wrappers="$CODEX/hooks"
  if command -v shellcheck >/dev/null 2>&1 &&
     shellcheck -S warning \
       "$wrappers/north-on-spawn-codex" \
       "$wrappers/north-on-tooluse-codex" \
       "$wrappers/north-mark-delegated-codex" \
       "$wrappers/north-on-stop-codex" \
       "$wrappers/north-on-terminal-codex"; then
    ok_detail 'Codex managed lifecycle adapters pass shellcheck'
  else
    bad 'Codex managed lifecycle adapter fails shellcheck'
  fi

  if [ "$LOCAL" -eq 1 ]; then
    local generation_exact=1
    local north_revision beagle_revision source_repo source_revision
    local immutable_source
    if cmp -s "$CODEX_REQUIREMENTS" /etc/codex/requirements.toml; then :
    else
      generation_exact=0
      bad 'Codex managed requirements are not the current /etc generation'
    fi
    for adapter in "${provider_adapters[@]}"; do
      live="/etc/codex/hooks/$adapter"
      expected_adapter="$LIVE_AGENT_ROOT/current/provider-hooks/$adapter"
      if [ -L "$live" ] && [ "$(readlink "$live")" = "$expected_adapter" ]; then :
      else
        generation_exact=0
        bad "Codex provider adapter $live is not the stable link to $expected_adapter"
      fi
    done
    # North and Beagle enforcement is attested against the active promote record.
    north_revision="$(promote_record_revision north 2>/dev/null || true)"
    beagle_revision="$(promote_record_revision beagle 2>/dev/null || true)"
    if [ -n "$north_revision" ] && [ -n "$beagle_revision" ]; then
      ok_detail "Enforcement promote record pins North@${north_revision:0:12} and Beagle@${beagle_revision:0:12}"
    else
      generation_exact=0
      bad "Enforcement promote record is missing or malformed: $(promote_record_path)"
    fi
    for spec in "${source_specs[@]:1}"; do
      IFS='|' read -r relative source_expr expected_checkout authority \
        git_blob_path promoted_path <<<"$spec"
      live="/etc/codex/hooks/$relative"
      resolved="$(readlink -f "$live" 2>/dev/null || true)"
      source_repo=''
      source_revision=''
      case "$authority" in
        self) ;;
        north)
          source_repo="$(git -C "$(dirname "$expected_checkout")" \
            rev-parse --show-toplevel 2>/dev/null || true)"
          source_revision="$north_revision"
          ;;
        beagle)
          source_repo="$(git -C "$(dirname "$expected_checkout")" \
            rev-parse --show-toplevel 2>/dev/null || true)"
          source_revision="$beagle_revision"
          ;;
      esac
      if [ -n "$promoted_path" ]; then
        immutable_source=sealed_promoted
        sealed_promoted_file "$live" "$promoted_path" && immutable_source=ok
      else
        immutable_source=store
        [ -n "$resolved" ] && [[ "$resolved" = /nix/store/* ]] && immutable_source=ok
      fi
      if [ "$immutable_source" = ok ] &&
         managed_hook_source_matches \
           "$live" "$expected_checkout" "$authority" "$source_repo" \
           "$source_revision" "$git_blob_path"; then :
      elif [ "$authority" = self ]; then
        generation_exact=0
        bad "Codex managed hook $live is not the exact store-backed Firn source"
      elif [ -n "$promoted_path" ]; then
        generation_exact=0
        bad "Codex managed hook $live is not a sealed promoted file exact to $authority@${source_revision:-missing}:$git_blob_path"
      else
        generation_exact=0
        bad "Codex managed hook $live is not exact to $authority@${source_revision:-missing}:$git_blob_path"
      fi
    done
    for source in "${runtimes[@]}"; do
      IFS='|' read -r runtime package binary <<<"$source"
      live="/etc/codex/hooks/runtime/$runtime"
      resolved="$(readlink -f "$live" 2>/dev/null || true)"
      if [ -x "$live" ] && [[ "$resolved" = /nix/store/* ]]; then :
      else
        generation_exact=0
        bad "Codex runtime $live is missing, non-executable, or not store-backed"
      fi
    done
    resolved="$(readlink -f /etc/codex/hooks/north 2>/dev/null || true)"
    if managed_source_root_matches "$HOME/code/north/main" "$resolved"; then :
    else
      generation_exact=0
      bad 'Codex North hook runtime does not resolve to the live North checkout'
    fi
    local interactive_codex managed_codex
    interactive_codex="$(command -v codex 2>/dev/null || true)"
    managed_codex="$(readlink -f /etc/codex/runtime/bin/codex 2>/dev/null || true)"
    interactive_codex="$(readlink -f "$interactive_codex" 2>/dev/null || true)"
    if [ -n "$managed_codex" ] && [[ "$managed_codex" = /nix/store/* ]] &&
       [ -x "$managed_codex" ]; then
      ok_detail 'Managed Codex is an exact immutable executable'
    else
      generation_exact=0
      bad 'Managed Codex runtime marker is missing, mutable, or non-executable'
    fi
    if [ -n "$interactive_codex" ] && [ "$interactive_codex" = "$managed_codex" ]; then
      ok_detail 'Interactive Codex directly resolves to the managed provider executable'
    elif [ -n "$interactive_codex" ]; then
      ok_detail 'Interactive Codex uses a distinct user launcher; managed provider authority remains the immutable runtime marker'
    else
      soft 'Interactive Codex is absent from PATH; managed provider authority remains independently attested'
    fi
    for relative in \
      bin/north-on-spawn \
      bin/north-on-tooluse \
      bin/north-mark-delegated \
      bin/north-on-stop \
      bin/north-on-terminal; do
      if [ -x "/etc/codex/hooks/north/$relative" ]; then :
      else
        generation_exact=0
        bad "Codex North runtime $relative is missing or non-executable in the live checkout"
      fi
    done
    if [ "$generation_exact" -eq 1 ]; then
      CODEX_HOOK_PROVENANCE='sealed promoted enforcement · immutable Firn generation · live North runtime'
      ok_detail 'Codex hook deployment is exact: sealed promoted enforcement plus the declared live North runtime'
    else
      CODEX_HOOK_PROVENANCE='generation drift detected'
    fi
  else
    CODEX_HOOK_PROVENANCE='immutable /nix/store generation deferred to --local'
  fi
}

before=$fail
need_toml "$CODEX/config.toml" 'Codex config'
if grep -Fq '{:source (s flakeRoot "/dotfiles/codex/config.toml")}' \
     "$REPO/modules/codex/default.bnix" &&
   grep -Fq '".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";' \
     "$REPO/modules/codex/default.nix" &&
   ! rg -q 'code/nixos-config/dotfiles/codex/config\.toml' \
     "$REPO/modules/codex/default.bnix" "$REPO/modules/codex/default.nix"; then
  ok_detail 'Codex config is a generation-owned store source'
else
  bad 'Codex config must use the committed flake source'
fi
validate_codex_managed_policy
codex_bindings="${CODEX_MANAGED_BINDINGS:-invalid}"
codex_hook_provenance="${CODEX_HOOK_PROVENANCE:-declaration drift detected}"
codex_north='declared; canonical explicit instance env; live probe deferred'
codex_linear='authentication deferred to an interactive credential check'
if [ "$COORDINATION_ACTIVE" -eq 0 ]; then
  codex_north='declared but inactive in the North generation; not probed'
fi
grep -q '^\[mcp_servers\.north\]' "$CODEX/config.toml" || bad "Codex config does not declare North MCP"
grep -q '^\[mcp_servers\.linear-mcp-msa-new\]' "$CODEX/config.toml" || bad "Codex config does not declare Linear MCP"
if codex_mcp_command_error="$(codex_mcp_commands_are_immutable "$CODEX/config.toml" 2>&1)"; then
  ok_detail "Codex North MCP command uses an immutable system-generation executable"
else
  codex_north='declared; mutable command drift detected'
  bad "Codex MCP command is not immutable: $codex_mcp_command_error"
fi
codex_north_env_ok=0
if codex_north_env_error="$(codex_north_env_is_canonical "$CODEX/config.toml" 2>&1)"; then
  codex_north_env_ok=1
  ok_detail "Codex North MCP has exactly the canonical explicit instance environment"
else
  codex_north='declared; explicit instance env drift detected'
  bad "Codex North MCP environment is not exact: $codex_north_env_error"
fi
if [ "$LOCAL" -eq 1 ]; then
  immutable_store_link_matches \
    "$HOME/.codex/config.toml" "$CODEX/config.toml" "$HOME/.codex/config.toml"
  canonical_link "$HOME/.codex/AGENTS.md" "$LIVE_AGENT_ROOT/current/instructions/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
  if [ -d "$HOME/.codex/skills" ] && [ ! -L "$HOME/.codex/skills" ]; then
    ok_detail 'Codex skills remains a provider/user-owned directory'
  else
    bad 'Codex skills must remain a real directory; North owns only exact compatibility links inside it'
  fi
  if [ "$COORDINATION_ACTIVE" -eq 0 ]; then
    ok_detail 'Codex MCP inventory skipped because coordination is disabled'
  elif command -v codex >/dev/null 2>&1; then
    codex_mcp_status=0
    mcp_output="$(
      CODEX_HOME="$HOME/.codex" \
      CODEX_SQLITE_HOME="$HOME/.codex/sqlite" \
        run_codex_mcp_inventory "${MCP_PROBE_TIMEOUT_SECONDS:-20}" 2>&1
    )" || codex_mcp_status=$?
    if [ "$codex_mcp_status" -eq 0 ]; then
      codex_inventory_ok=1
      for server in north; do
        if ! codex_mcp_inventory_server_has_state \
          "$mcp_output" "$server" true; then
          bad "Codex MCP '$server' is missing, duplicated, or disabled"
          codex_inventory_ok=0
        fi
      done
      if ! codex_mcp_inventory_server_has_state \
        "$mcp_output" linear-mcp-msa-new false; then
        bad 'Codex noninteractive inventory did not exclude the Linear OAuth server'
        codex_inventory_ok=0
      fi
      if [ "$codex_inventory_ok" -eq 1 ]; then
        ok_detail "Codex config parsed; North enabled; Linear OAuth excluded from the noninteractive inventory"
        if [ "$codex_north_env_ok" -eq 1 ]; then
          codex_north='enabled; canonical explicit instance env'
        else
          codex_north='enabled; explicit instance env drift detected'
        fi
      fi
      codex_linear='authentication unverified; interactive credential check deferred'
      soft 'Codex Linear OAuth authentication is not inspected noninteractively; when needed, run: codex mcp login linear-mcp-msa-new'
    elif [ "$codex_mcp_status" -eq 124 ]; then
      bad "Codex noninteractive MCP inventory timed out after ${MCP_PROBE_TIMEOUT_SECONDS:-20}s; its process group was reaped"
    else
      bad "codex rejected its noninteractive MCP inventory (exit $codex_mcp_status):\n$mcp_output"
    fi
  else bad "codex CLI is missing from PATH"; fi
fi
provider_group Codex "$before" \
  "Hooks       $codex_bindings managed authoritative bindings" \
  'Identity    managed lanes harness-owned · pinned native fallback → openai' \
  'Topology    sole policy: managed /etc/codex/hooks' \
  "Hook source $codex_hook_provenance" \
  'Bootstrap   static config parsed' \
  "MCP         North: $codex_north" \
  "            Linear: $codex_linear"

before=$fail
openai_installed='not probed'
openai_authenticated='not probed'
openai_headroom='not probed'
openai_routing='not probed'
allocation_summary='not probed'
if [ "$LOCAL" -eq 1 ] && [ "$COORDINATION_ACTIVE" -eq 0 ]; then
  ok_detail 'Provider probes skipped because coordination is disabled'
elif [ "$LOCAL" -eq 1 ]; then
  openai_installed='unknown'
  openai_authenticated='unknown'
  openai_headroom='unknown'
  openai_routing='unknown'
  if command -v "${NORTH_PACKAGED_BIN:-north-packaged}" >/dev/null 2>&1; then
    if provider_output="$(run_north_packaged providers --json 2>&1)"; then
      if openai_fields="$(printf '%s\n' "$provider_output" | "$REPO/scripts/agent-provider-status.sh" openai)"; then
        IFS='|' read -r openai_installed openai_authenticated openai_headroom openai_routing <<<"$openai_fields"
        [ "$openai_installed" = yes ] || bad "North reports OpenAI/Codex not installed"
        [ "$openai_authenticated" = yes ] || bad "North reports OpenAI/Codex not authenticated"
      else bad "North omitted or malformed OpenAI capability status:\n$provider_output"; fi
      if allocation_summary="$(jq -er '
        .allocationMode as $mode
        | if ($mode == "balanced" or $mode == "preferential" or $mode == "reserved") then
            ([.providers[]?.targets[]? | select(.routing == "eligible")] | length) as $eligible
            | if $eligible > 0 then "\($mode) · \($eligible) eligible accounts"
              else error("no eligible routing accounts") end
          else error("unsupported allocation mode") end
      ' <<<"$provider_output")"; then
        :
      else bad "North allocation policy missing or malformed:\n$provider_output"; fi
      provider_source="$(jq -r '.source // "unknown source"' <<<"$provider_output")"
      provider_target_count="$(jq '[.providers[]?.targets[]?] | length' <<<"$provider_output")"
      if provider_schema_version="$(north_provider_schema_version <<<"$provider_output")"; then
        ok_detail "North providers JSON v$provider_schema_version · $provider_target_count targets · $provider_source"
      else
        bad "North providers schemaVersion is missing or malformed:\n$provider_output"
      fi
    else
      provider_status=$?
      if [ "$provider_status" -eq 124 ]; then
        bad "packaged North provider readiness timed out after ${NORTH_PROBE_TIMEOUT_SECONDS:-15}s; its process group was reaped"
      else
        bad "packaged North provider readiness failed (exit $provider_status):\n$provider_output"
      fi
    fi
  else bad "north-packaged is missing from PATH"; fi
else ok_detail "provider readiness deferred to --local"; fi
if [ "$LOCAL" -eq 1 ]; then
  provider_group North "$before" \
    'Surface     CLI/MCP only · web deployment retired' \
    "OpenAI      installed=$openai_installed · authenticated=$openai_authenticated · routing=$openai_routing · headroom=$openai_headroom" \
    "Allocation  ${allocation_summary:-unknown}"
else
  provider_group North "$before" \
    'Providers   readiness deferred to --local'
fi

# --- worktree layout -------------------------------------------------------
# A rule with no detector silently stops being true. On 2026-07-29 a sweep found
# 63 worktrees across FOUR conventions at once, plus seven clones of north at
# ~/code root and orphaned trees whose gitdir no longer existed — after the
# layout had been written down and restated repeatedly. This is the detector.
if [ "$LOCAL" -eq 1 ] && command -v worktree-layout-check >/dev/null 2>&1; then
  if worktree_layout_out="$(worktree-layout-check 2>&1)"; then
    printf '\u2713 %s\n' "$worktree_layout_out"
  else
    bad "worktree layout drift — run worktree-layout-check for the list"
    printf '%s\n' "$worktree_layout_out" >&2
  fi
fi

if [ "$fail" -ne 0 ]; then printf 'agent-config-check: FAILED\n' >&2; exit 1; fi
if [ "$warn" -gt 0 ]; then printf 'agent-config-check: passed with %s warning(s)\n' "$warn"
else printf 'agent-config-check: all green\n'; fi
