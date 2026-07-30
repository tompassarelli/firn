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

run_claude_probe() {
  local duration="$1"
  shift
  run_bounded_process "$duration" \
    /run/current-system/sw/bin/env -u CLAUDE_CONFIG_DIR \
    "${CLAUDE_BIN:-/run/current-system/sw/bin/claude}" "$@"
}

claude_probe_binary_is_authoritative() {
  local configured="${CLAUDE_BIN:-/run/current-system/sw/bin/claude}" resolved

  [ -x "$configured" ] || return 1
  if [ -n "${CLAUDE_BIN:-}" ]; then
    return 0
  fi
  [ "$configured" = /run/current-system/sw/bin/claude ] || return 1
  resolved="$(readlink -f "$configured" 2>/dev/null)" || return 1
  [[ "$resolved" = /nix/store/* ]] && [ -x "$resolved" ]
}

claude_mcp_server_connected() {
  local output="$1" server="$2"
  local -a lines=()

  mapfile -t lines < <(grep -F "${server}:" <<<"$output" || true)
  [ "${#lines[@]}" -eq 1 ] || return 1
  [[ "${lines[0]}" = "$server:"* ]] || return 1
  [[ "${lines[0]}" = *'✔ Connected'* ]] || return 1
  [[ "${lines[0]}" != *'! Connected'* ]]
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
    "FRAM_LOG": "/home/tom/.local/state/north/coordination.log",
    "FRAM_TELEMETRY_LOG": "/home/tom/.local/state/north/telemetry.log",
    "FRAM_THREADS": "/home/tom/.local/state/north/threads",
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
    "fram": "/run/current-system/sw/bin/fram-mcp",
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

# Classify the executable path from systemctl's structured ExecStart rendering.
# The unit owns one immutable launcher; that launcher owns the mutable, exact-
# revision selector. A direct Fram executable would recreate the supervisor race
# and bypass selector validation, even when that executable happens to be in the
# Nix store.
classify_north_coord_exec() {
  local exec_spec="$1" path=''

  NORTH_COORD_EXEC_KIND='unrecognized'
  NORTH_COORD_EXEC_PATH=''
  if [[ "$exec_spec" =~ path=([^[:space:]\;]+) ]]; then
    path="${BASH_REMATCH[1]}"
  else
    path="${exec_spec%% *}"
  fi
  NORTH_COORD_EXEC_PATH="$path"

  if [[ "$path" =~ ^/nix/store/[a-z0-9]{32}-north-coord-runtime/bin/north-coord-runtime$ ]]; then
    NORTH_COORD_EXEC_KIND='runtime-selector'
    return 0
  fi
  if [[ "$path" =~ ^/nix/store/[a-z0-9]{32}-north-coord-sd-listen-checked/bin/north-coord-sd-listen$ ]] &&
     [[ "$exec_spec" =~ /nix/store/[a-z0-9]{32}-north-coord-runtime/bin/north-coord-runtime[[:space:]]+start ]]; then
    # Socket activation deliberately inserts one immutable fd-validation
    # launcher ahead of the same runtime selector. Accept only the complete
    # wrapper -> selector chain; the wrapper by itself is not runtime authority.
    NORTH_COORD_EXEC_KIND='socket-runtime-selector'
    return 0
  fi
  if [[ "$path" =~ ^/nix/store/[a-z0-9]{32}-north-coord-slot-start/bin/north-coord-slot-start$ ]]; then
    NORTH_COORD_EXEC_KIND='slot-runtime-selector'
    return 0
  fi
  if [[ "$path" =~ ^/nix/store/[a-z0-9]{32}-fram[^/]*/bin/fram-daemon$ ]]; then
    NORTH_COORD_EXEC_KIND='direct-package'
    return 1
  fi
  case "$path" in
    */code/fram/main/bin/fram-daemon)
      NORTH_COORD_EXEC_KIND='direct-checkout'
      ;;
  esac
  return 1
}

environment_lines_value() {
  local environment="$1" key="$2" line value='' count=0

  while IFS= read -r line; do
    case "$line" in
      "$key="*)
        value=${line#*=}
        count=$((count + 1))
        ;;
    esac
  done <<<"$environment"
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$value"
}

select_north_coord_runtime_state() {
  local process_env="$1" unit="$2" exec_kind="$3"
  local slot state slot_runtime

  NORTH_COORD_RUNTIME_STATE_ROOT=''
  NORTH_COORD_RUNTIME_STATE_REASON=''
  case "$exec_kind" in
    runtime-selector|socket-runtime-selector)
      [ "$unit" = north-coord.service ] || {
        NORTH_COORD_RUNTIME_STATE_REASON="legacy selector is attached to unexpected unit: $unit"
        return 1
      }
      NORTH_COORD_RUNTIME_STATE_ROOT="$HOME/.local/state/north/fram-runtime"
      ;;
    slot-runtime-selector)
      slot="$(environment_lines_value "$process_env" NORTH_COORD_SLOT 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_STATE_REASON='slot process identity is missing or duplicated'
        return 1
      }
      case "$slot" in
        blue|green) ;;
        *)
          NORTH_COORD_RUNTIME_STATE_REASON="slot process identity is invalid: ${slot:-missing}"
          return 1
          ;;
      esac
      [ "$unit" = "north-coord-$slot.service" ] || {
        NORTH_COORD_RUNTIME_STATE_REASON="slot $slot does not match systemd unit $unit"
        return 1
      }
      state="$(environment_lines_value "$process_env" NORTH_COORD_RUNTIME_STATE 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_STATE_REASON='slot runtime state is missing or duplicated'
        return 1
      }
      [ "$state" = "$HOME/.local/state/north/fram-runtime-$slot" ] || {
        NORTH_COORD_RUNTIME_STATE_REASON="slot $slot runtime state is noncanonical: ${state:-missing}"
        return 1
      }
      slot_runtime="$(environment_lines_value "$process_env" NORTH_COORD_SLOT_RUNTIME 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_STATE_REASON='slot runtime executable is missing or duplicated'
        return 1
      }
      [[ "$slot_runtime" =~ ^/nix/store/[a-z0-9]{32}-north-coord-${slot}-runtime/bin/north-coord-${slot}-runtime$ ]] || {
        NORTH_COORD_RUNTIME_STATE_REASON="slot $slot runtime executable is not immutable and slot-scoped: ${slot_runtime:-missing}"
        return 1
      }
      NORTH_COORD_RUNTIME_STATE_ROOT="$state"
      ;;
    *)
      NORTH_COORD_RUNTIME_STATE_REASON="unsupported coordinator selector kind: ${exec_kind:-missing}"
      return 1
      ;;
  esac
}

north_coord_process_birth_token() {
  local pid="$1" stat_line remainder start_ticks
  local -a fields

  [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/stat" ]] || return 1
  stat_line="$(<"/proc/$pid/stat")"
  remainder=${stat_line##*) }
  read -r -a fields <<<"$remainder"
  start_ticks=${fields[19]:-}
  [[ "$start_ticks" =~ ^[0-9]+$ ]] || return 1
  printf 'proc:%s\n' "$start_ticks"
}

# The ACTIVE coordinator unit. Under blue/green the legacy `north-coord.service`
# is deliberately inactive (gated on
# ConditionPathExists=!/var/lib/north-coord-cutover/bootstrap-complete), so
# testing that name reports "north-coord systemd service is not active" on a
# perfectly healthy system — observed 2026-07-29 with blue and green both active
# and `north show` answering in 107ms. A health check that fails green is worse
# than no check, because the next real failure gets ignored.
#
# The route map names the live slot; the direct probes are the fallback, and the
# legacy unit remains last so a pre-cutover system still resolves.
resolve_north_coord_unit() {
  local slot candidate
  slot="$(awk 'NF>=2 && $1=="active" {print $2; exit}' \
            /var/lib/north-coord-cutover/route.map 2>/dev/null || true)"
  for candidate in ${slot:+"north-coord-${slot}.service"} \
                   north-coord-green.service north-coord-blue.service \
                   north-coord.service; do
    if systemctl is-active --quiet "$candidate" 2>/dev/null; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}
NORTH_COORD_UNIT="${NORTH_COORD_UNIT:-north-coord.service}"



north_coord_runtime_record_value() {
  local record="$1" key="$2" line value='' count=0

  while IFS= read -r line; do
    case "$line" in
      "$key="*)
        value=${line#*=}
        count=$((count + 1))
        ;;
    esac
  done <"$record"
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$value"
}

north_coord_runtime_record_owner_is_valid() {
  local process_env="$1" main_pid="$2" active_generation_link="$3"
  local owner_token generation runtime_file canonical_generation canonical_active
  local canonical_runtime_file record_stat expected_birth record_value

  NORTH_COORD_RUNTIME_OWNER_REASON=''
  owner_token="$(environment_lines_value "$process_env" FRAM_RUNTIME_OWNER_TOKEN 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_OWNER_REASON='process owner token is missing or duplicated'
    return 1
  }
  [[ "$owner_token" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || {
    NORTH_COORD_RUNTIME_OWNER_REASON='process owner token is not a lowercase UUID'
    return 1
  }
  [[ "$main_pid" =~ ^[1-9][0-9]*$ ]] || {
    NORTH_COORD_RUNTIME_OWNER_REASON='systemd MainPID is invalid'
    return 1
  }
  generation="$(environment_lines_value "$process_env" NORTH_COORD_RUNTIME_GENERATION 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_OWNER_REASON='process runtime generation is missing or duplicated'
    return 1
  }
  runtime_file="$(environment_lines_value "$process_env" NORTH_COORD_RUNTIME_FILE 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_OWNER_REASON='process runtime record path is missing or duplicated'
    return 1
  }
  canonical_generation="$(realpath -e "$generation" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_OWNER_REASON="process runtime generation is missing: $generation"
    return 1
  }
  [ "$generation" = "$canonical_generation" ] &&
    [ -d "$generation" ] && [ ! -L "$generation" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='process runtime generation is not a canonical real directory'
      return 1
    }
  [ -L "$active_generation_link" ] || {
    NORTH_COORD_RUNTIME_OWNER_REASON="active generation selector is not a symlink: $active_generation_link"
    return 1
  }
  canonical_active="$(readlink -f "$active_generation_link" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_OWNER_REASON='active generation selector cannot be resolved'
    return 1
  }
  [ "$canonical_generation" = "$canonical_active" ] || {
    NORTH_COORD_RUNTIME_OWNER_REASON='process generation is not the active runtime generation'
    return 1
  }
  [ "$runtime_file" = "$canonical_generation/active.runtime" ] &&
    [ -f "$runtime_file" ] && [ ! -L "$runtime_file" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='process runtime record is not the active generation record'
      return 1
    }
  canonical_runtime_file="$(realpath -e "$runtime_file" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record cannot be resolved'
    return 1
  }
  [ "$canonical_runtime_file" = "$runtime_file" ] || {
    NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record path is not canonical'
    return 1
  }
  record_stat="$(stat -c '%u:%a:%h' "$runtime_file" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record metadata is unreadable'
    return 1
  }
  [ "$record_stat" = "$EUID:600:1" ] || {
    NORTH_COORD_RUNTIME_OWNER_REASON="active runtime record ownership/mode/link-count is unsafe: $record_stat"
    return 1
  }
  expected_birth="$(north_coord_process_birth_token "$main_pid")" || {
    NORTH_COORD_RUNTIME_OWNER_REASON='systemd MainPID birth identity is unreadable'
    return 1
  }

  record_value="$(north_coord_runtime_record_value "$runtime_file" FORMAT 2>/dev/null)" &&
    [ "$record_value" = north-fram-active-runtime/v1 ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record format is invalid'
      return 1
    }
  record_value="$(north_coord_runtime_record_value "$runtime_file" GENERATION 2>/dev/null)" &&
    [ "$record_value" = "$canonical_generation" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record generation does not match the process generation'
      return 1
    }
  record_value="$(north_coord_runtime_record_value "$runtime_file" PID 2>/dev/null)" &&
    [ "$record_value" = "$main_pid" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record PID does not match systemd MainPID'
      return 1
    }
  record_value="$(north_coord_runtime_record_value "$runtime_file" PID_BIRTH 2>/dev/null)" &&
    [ "$record_value" = "$expected_birth" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record process birth does not match systemd MainPID'
      return 1
    }
  record_value="$(north_coord_runtime_record_value "$runtime_file" OWNER_TOKEN 2>/dev/null)" &&
    [ "$record_value" = "$owner_token" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='process owner token does not match the active runtime record'
      return 1
    }
  record_value="$(north_coord_runtime_record_value "$runtime_file" CONTROLLER_UNIT 2>/dev/null)" &&
    [ "$record_value" = "$NORTH_COORD_UNIT" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record controller unit is invalid'
      return 1
    }
  record_value="$(north_coord_runtime_record_value "$runtime_file" CONTROLLER_MAIN_PID 2>/dev/null)" &&
    [ "$record_value" = "$main_pid" ] || {
      NORTH_COORD_RUNTIME_OWNER_REASON='active runtime record controller PID does not match systemd MainPID'
      return 1
    }
  return 0
}

north_coord_runtime_identity_is_valid() {
  local mode="$1" source="$2" revision="$3" tree="$4" origin="$5" daemon="$6" selector="$7"
  local store_root="${8:-/nix/store}"
  local canonical_source canonical_selector canonical_daemon canonical_origin
  local canonical_store_root expected_source expected_daemon package_name
  local observed_revision observed_tree observed_common observed_origin top_level worktree_status

  NORTH_COORD_RUNTIME_IDENTITY_REASON=''
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON='revision is not an exact Git SHA'
    return 1
  }
  # Requires root context: reads a root-owned symlink.
  [ -L "$selector" ] || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON="stable selector is not a symlink: $selector"
    return 1
  }
  [ "$(readlink "$selector")" = active/current ] || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON="stable selector target is substituted: $selector"
    return 1
  }
  canonical_source="$(realpath -e "$source" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON="runtime source is missing: $source"
    return 1
  }
  canonical_selector="$(readlink -f "$selector" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON="stable selector cannot be resolved: $selector"
    return 1
  }
  canonical_daemon="$(realpath -e "$daemon" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON="runtime daemon is missing: $daemon"
    return 1
  }

  case "$mode" in
    checkout)
      [ "$canonical_source" = "$canonical_selector" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source and stable selector resolve differently'
        return 1
      }
      expected_daemon="$canonical_source/bin/fram-daemon"
      [ -x "$expected_daemon" ] && [ "$canonical_daemon" = "$expected_daemon" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout daemon is not the selected physical Fram daemon'
        return 1
      }
      expected_source="$(realpath -m "$(dirname "$selector")/deployments/$revision")"
      [ "$canonical_source" = "$expected_source" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source is outside its revision-owned deployment path'
        return 1
      }
      [ -d "$source" ] && [ ! -L "$source" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout deployment is not a real directory'
        return 1
      }
      top_level="$(git -C "$canonical_source" rev-parse --show-toplevel 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source is not a Git worktree root'
        return 1
      }
      [ "$(realpath -e "$top_level" 2>/dev/null)" = "$canonical_source" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source is not its Git worktree root'
        return 1
      }
      if git -C "$canonical_source" symbolic-ref -q HEAD >/dev/null 2>&1; then
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source HEAD is attached to a mutable branch'
        return 1
      fi
      observed_revision="$(git -C "$canonical_source" rev-parse --verify HEAD 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source has no readable Git HEAD'
        return 1
      }
      [ "$observed_revision" = "$revision" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source HEAD differs from declared revision'
        return 1
      }
      [[ "$tree" =~ ^[0-9a-f]{40}$ ]] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout tree is not an exact Git object ID'
        return 1
      }
      observed_tree="$(git -C "$canonical_source" rev-parse --verify 'HEAD^{tree}' 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source tree is unreadable'
        return 1
      }
      [ "$observed_tree" = "$tree" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source tree differs from declared tree'
        return 1
      }
      observed_common="$(git -C "$canonical_source" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source origin is unreadable'
        return 1
      }
      case "$observed_common" in
        */.git) observed_origin=${observed_common%/.git} ;;
        *) observed_origin=$observed_common ;;
      esac
      observed_origin="$(realpath -e "$observed_origin" 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source origin cannot be canonicalized'
        return 1
      }
      [ "$observed_origin" = "$origin" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source origin differs from declared origin'
        return 1
      }
      git -C "$canonical_source" diff --quiet --no-ext-diff -- || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source has modified tracked files'
        return 1
      }
      git -C "$canonical_source" diff --cached --quiet --no-ext-diff -- || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source has staged tracked files'
        return 1
      }
      worktree_status="$(git -C "$canonical_source" status --porcelain=v1 --untracked-files=all 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source cleanliness is unreadable'
        return 1
      }
      [ -z "$worktree_status" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='checkout source has tracked or untracked worktree changes'
        return 1
      }
      ;;
    package)
      canonical_store_root="$(realpath -e "$store_root" 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON="Nix store root is missing: $store_root"
        return 1
      }
      canonical_origin="$(realpath -e "$origin" 2>/dev/null)" || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON="package origin is missing: $origin"
        return 1
      }
      package_name="${canonical_origin##*/}"
      [ "$(dirname "$canonical_origin")" = "$canonical_store_root" ] &&
        [[ "$package_name" =~ ^[a-z0-9]{32}-fram[^/]*$ ]] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package origin is not a direct Fram Nix-store root'
        return 1
      }
      [ "$origin" = "$canonical_origin" ] &&
        [ -d "$canonical_origin" ] && [ ! -L "$canonical_origin" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package origin does not name a canonical immutable directory'
        return 1
      }
      expected_source="$canonical_origin/libexec/fram"
      [ "$source" = "$expected_source" ] &&
        [ "$canonical_source" = "$expected_source" ] &&
        [ "$canonical_selector" = "$expected_source" ] &&
        [ -d "$source" ] && [ ! -L "$source" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package selector and source do not name the exact outer-package libexec/fram directory'
        return 1
      }
      expected_daemon="$canonical_origin/bin/fram-daemon"
      [ "$daemon" = "$expected_daemon" ] &&
        [ "$canonical_daemon" = "$expected_daemon" ] &&
        [ -f "$daemon" ] && [ ! -L "$daemon" ] && [ -x "$daemon" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package daemon is not the selected outer package wrapper'
        return 1
      }
      [ "$tree" = "immutable:$revision" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package tree marker does not bind its package revision'
        return 1
      }
      ;;
    *)
      NORTH_COORD_RUNTIME_IDENTITY_REASON="unknown runtime mode: $mode"
      return 1
      ;;
  esac
  return 0
}

systemd_environment_has() {
  local environment="$1" assignment="$2"
  [[ " $environment " == *" $assignment "* ]]
}

north_coord_listener_pids_from_ss() {
  grep -oE 'pid=[0-9]+' |
    cut -d= -f2 |
    sort -nu
}

north_coord_listener_set_matches_mainpid() {
  local main_pid=$1
  shift

  [[ "$main_pid" =~ ^[1-9][0-9]*$ && $# -eq 1 && "${1:-}" == "$main_pid" ]]
}

# Proxy-aware fallback: a listener need not be the north-coord MainPID itself
# if it is a member of the north-coord-proxy.service cgroup (the front door
# a fronting proxy owns) AND the runtime identity probe already confirmed the
# backing process. Bare cgroup membership without a validated identity is not
# sufficient authority.
north_coord_listener_in_proxy_cgroup() {
  local pid="$1"
  [ -r "/proc/$pid/cgroup" ] &&
    grep -Eq '^[^:]*:[^:]*:/system\.slice/north-coord-proxy\.service(/|$)' "/proc/$pid/cgroup"
}

north_coord_listeners_are_proxy_fronted() {
  local pid
  [ "$#" -gt 0 ] || return 1
  for pid in "$@"; do
    north_coord_listener_in_proxy_cgroup "$pid" || return 1
  done
  return 0
}

# Cheap, non-root-sensitive substitute for the old
# north_coord_runtime_identity_is_valid gate: shells out to the installed
# `north coord-safety` command and requires both a clean exit and the
# expected confirmation string on stdout.
north_coord_safety_ok() {
  command -v north >/dev/null 2>&1 || return 1
  local out
  out="$(north coord-safety 2>/dev/null)" || return 1
  grep -Fq 'coordinator runtime identity OK on :7977' <<<"$out"
}

# Codex stores per-hook trust/enablement by numeric manifest coordinates. Resolve
# disabled entries back to their event and command so drift reports name the
# behavior that was actually turned off instead of an opaque `0:1` key.
list_disabled_codex_hooks() {
  local manifest="$1" config="$2"
  local state_manifest="${3:-/home/tom/.codex/hooks.json}"
  python3 - "$manifest" "$config" "$state_manifest" <<'PY'
import json
import re
import sys
import tomllib

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
with open(sys.argv[2], "rb") as handle:
    config = tomllib.load(handle)

hooks = manifest.get("hooks", {})

def normalized(value):
    return re.sub(r"[^a-z0-9]", "", value.lower())

event_by_key = {normalized(name): name for name in hooks}
states = config.get("hooks", {}).get("state", {})
for key, state in states.items():
    if not isinstance(state, dict) or state.get("enabled") is not False:
        continue
    manifest_path = "unknown"
    event_key = "unknown"
    group_raw = "?"
    hook_raw = "?"
    try:
        manifest_path, event_key, group_raw, hook_raw = key.rsplit(":", 3)
        if manifest_path not in (sys.argv[1], sys.argv[3]):
            continue
        group_index = int(group_raw)
        hook_index = int(hook_raw)
        event = event_by_key[normalized(event_key)]
        command = hooks[event][group_index]["hooks"][hook_index]["command"]
    except (KeyError, IndexError, TypeError, ValueError):
        event = event_by_key.get(normalized(event_key), event_key)
        command = "<unresolved manifest coordinate>"
    print(f"{event}\t{group_raw}:{hook_raw}\t{command}")
PY
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

expected = {
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
        "PreToolUse": [
            {
                "matcher": "^(Agent|Task|Workflow)$",
                "hooks": [command("agent-spawn-guard.sh", 10)],
            },
            {
                "matcher": "^(Edit|Write|MultiEdit|apply_patch)$",
                "hooks": [
                    command("code-upstream-guard.sh", 10),
                    command("firn-guard.sh", 10),
                    command("north-clock-guard-codex", 10),
                    command("launch-critical-worktree-guard.sh", 10),
                ],
            },
            {
                "matcher": "^Bash$",
                "hooks": [
                    command("agent-spawn-guard.sh", 10),
                    command("tripwire-guard.sh", 10),
                    command("firn-guard.sh", 10),
                    command("north-clock-guard-codex", 10),
                    command("launch-critical-worktree-guard.sh", 10),
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
                "hooks": [
                    command("racket-build-guard.sh", 15),
                    command("north-on-tooluse-codex", 10),
                ],
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

with open(sys.argv[1], "rb") as handle:
    policy = tomllib.load(handle)
if type(policy.get("allow_managed_hooks_only")) is not bool:
    raise SystemExit("allow_managed_hooks_only must be a boolean")
if type(policy.get("allow_remote_control")) is not bool:
    raise SystemExit("allow_remote_control must be a boolean")
if type(policy.get("managed_hook_failure_mode")) is not str:
    raise SystemExit("managed_hook_failure_mode must be a string")
if policy["managed_hook_failure_mode"] != "block":
    raise SystemExit("managed_hook_failure_mode must be block")
if policy != expected:
    raise SystemExit("managed Codex policy differs from the canonical contract")
print(sum(
    len(binding["hooks"])
    for event, bindings in policy["hooks"].items()
    if event != "managed_dir"
    for binding in bindings
))
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

  if [ ! -L "$link" ]; then
    bad "$label must be a generation-owned symlink"
    return 1
  fi
  resolved="$(readlink -f "$link" 2>/dev/null || true)"
  case "$resolved" in
    /nix/store/*) ;;
    *)
      bad "$label resolves outside /nix/store: ${resolved:-missing}"
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
    north|beagle|fram)
      locked_git_blob_matches_file \
        "$live" "$source_repo" "$revision" "$git_blob_path"
      ;;
    *) return 1 ;;
  esac
}

flake_locked_revision() {
  local lock="$1" node="$2"

  jq -er --arg node "$node" '
    .nodes[$node].locked.rev | select(test("^[0-9a-f]{40}$"))
  ' "$lock"
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

writable_claude_settings_match_control_plane() {
  local live="$1" baseline="$2" label="$3" link_count

  if [ ! -f "$live" ] || [ -L "$live" ] || [ ! -O "$live" ] || [ ! -w "$live" ]; then
    bad "$label must be a writable, user-owned regular file"
    return 1
  fi
  link_count="$(stat -c '%h' "$live" 2>/dev/null || true)"
  if [ "$link_count" != 1 ]; then
    bad "$label must not share writable inode state (link count: ${link_count:-unknown})"
    return 1
  fi
  if python3 - "$live" "$baseline" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    live = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    baseline = json.load(handle)

if live.get("hooks") != baseline.get("hooks"):
    raise SystemExit("live hook control plane differs from the committed seed")
if live.get("statusLine") != baseline.get("statusLine"):
    raise SystemExit("live statusLine differs from the committed seed")

checkout_command = re.compile(r"/home/tom/code/(?:north|fram)/bin/")
for event_groups in live.get("hooks", {}).values():
    for group in event_groups:
        for hook in group.get("hooks", []):
            command = hook.get("command")
            if isinstance(command, str) and checkout_command.search(command):
                raise SystemExit(f"live hook uses mutable checkout command: {command}")
PY
  then
    ok_detail "$label is writable runtime state with the generation-owned hook control plane"
  else
    bad "$label does not preserve the committed immutable hook control plane"
    return 1
  fi
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
FRAM_INTEGRATION="${AGENT_CONFIG_FRAM_INTEGRATION:-$HOME/code/fram/main/integrations/north}"
FIRN_INTEGRATION="$REPO/modules/north-profile/firn"
CLAUDE="${AGENT_CONFIG_CLAUDE:-$REPO/dotfiles/claude}"
CODEX="$REPO/dotfiles/codex"
LIVE_REPO="${AGENT_CONFIG_LIVE_REPO:-$HOME/code/nixos-config}"
LIVE_SHARED="${AGENT_CONFIG_LIVE_NORTH_PROFILE:-$HOME/code/north/main/profiles/tom}"
LIVE_SKILLS_FARM="${AGENT_CONFIG_LIVE_SKILLS_FARM:-$HOME/.local/state/north/skills}"
LIVE_NORTH_ROOT="${AGENT_CONFIG_LIVE_NORTH_ROOT:-$HOME/code/north}"
LIVE_BEAGLE_ROOT="${AGENT_CONFIG_LIVE_BEAGLE_ROOT:-$HOME/code/beagle}"
LIVE_FRAM_ROOT="${AGENT_CONFIG_LIVE_FRAM_ROOT:-$HOME/code/fram}"
LIVE_FIRN_ROOT="${AGENT_CONFIG_LIVE_FIRN_ROOT:-$HOME/code/nixos-config}"
LIVE_CLAUDE="$LIVE_REPO/dotfiles/claude"
LIVE_HERMES="$LIVE_REPO/dotfiles/hermes"
CODEX_REQUIREMENTS="$REPO/modules/codex/requirements.toml"
CODEX_LEGACY_HOOKS="${CODEX_LEGACY_HOOKS:-$CODEX/hooks.json}"
HERMES="${AGENT_CONFIG_HERMES:-$REPO/dotfiles/hermes}"
HERMES_BRIDGE="$HERMES/plugins/north-bridge"
HERMES_MODULE="${AGENT_CONFIG_HERMES_MODULE:-$REPO/modules/hermes/default.bnix}"
LAUNCHER_BIN="$REPO/dotfiles/bin"
LOCAL=0
VERBOSE=0
CANONICAL_FRAM_LOG="$HOME/.local/state/north/coordination.log"
CANONICAL_FRAM_TELEMETRY_LOG="$HOME/.local/state/north/telemetry.log"
CANONICAL_FRAM_THREADS="$HOME/.local/state/north/threads"
# MCP servers whose live-connection health is advisory-only, not FAIL-worthy.
CLIENT_SCOPED_MCP_SERVERS=(linear-mcp-msa-new)
for arg in "$@"; do
  case "$arg" in
    --local) LOCAL=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    *) printf 'usage: %s [--local] [--verbose]\n' "$0" >&2; exit 2 ;;
  esac
done

fail=0
warn=0
details=()
ok_detail() { details+=("ok: $*"); }
note() { [ "$VERBOSE" -eq 0 ] || printf '  note: %s\n' "$*"; }
bad() { printf '  FAIL: %s\n' "$*" >&2; fail=$((fail + 1)); }
soft() { printf '  warn: %s\n' "$*" >&2; warn=$((warn + 1)); }
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
note_ignored_codex_legacy_manifest() {
  local manifest="$1"
  if [ ! -e "$manifest" ]; then
    note "Codex legacy user hook manifest is absent (ignored by managed-only policy)"
  elif jq -e . "$manifest" >/dev/null 2>&1; then
    note "Codex legacy user hook manifest is present + valid JSON, but ignored"
  else
    note "Codex legacy user hook manifest is invalid JSON, but ignored"
  fi
  return 0
}

printf 'agent harness check%s\n' "$([ "$LOCAL" -eq 1 ] && printf ' (local)' || true)"

# North-composed constitution plus hook/skill implementations from each owner.
before=$fail
hook_count=0
if command -v shellcheck >/dev/null 2>&1; then
  for hook_root in \
    "$SHARED/hooks" \
    "$BEAGLE_INTEGRATION/hooks" \
    "$FRAM_INTEGRATION/hooks" \
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
  "$SHARED/skills" \
  "$BEAGLE_INTEGRATION/skills" \
    "$FRAM_INTEGRATION/skills" \
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
if [ -s "$SHARED/AGENTS.md" ]; then
  ok_detail "canonical AGENTS.md present"
elif [ "$LOCAL" -eq 1 ]; then
  bad "canonical AGENTS.md is missing or empty"
else
  note "North-composed AGENTS.md unavailable in repository-only mode"
fi
north_profile_module="$REPO/modules/north-profile/default.bnix"
for profile_member in AGENTS.md docs hooks; do
  if grep -Fq "\"/code/north/main/agent-profile/$profile_member\"" "$north_profile_module"; then
    ok_detail "~/.agents/$profile_member is wired to the North-composed profile"
  else
    bad "~/.agents/$profile_member must be wired to ~/code/north/main/agent-profile"
  fi
done
if grep -Fq '"/.local/state/north/skills"' "$north_profile_module"; then
  ok_detail '~/.agents/skills is wired to the atomic North skills farm'
else
  bad '~/.agents/skills must be wired to ~/.local/state/north/skills'
fi
if [ -e "$REPO/dotfiles/agents" ]; then
  bad "retired Firn-owned dotfiles/agents tree still exists"
fi
if [ -e "$REPO/dotfiles/claude/CLAUDE.md" ] ||
   [ -L "$REPO/dotfiles/claude/CLAUDE.md" ] ||
   [ -e "$REPO/dotfiles/claude/hooks" ] ||
   [ -L "$REPO/dotfiles/claude/hooks" ]; then
  bad "obsolete Claude redirect sources still exist after Home Manager took ownership"
fi
if [ "$LOCAL" -eq 1 ]; then
  canonical_link "$HOME/.agents/AGENTS.md" "$LIVE_SHARED/AGENTS.md" "$HOME/.agents/AGENTS.md"
  canonical_link "$HOME/.agents/docs" "$LIVE_SHARED/docs" "$HOME/.agents/docs"
  canonical_link "$HOME/.agents/hooks" "$LIVE_SHARED/hooks" "$HOME/.agents/hooks"
  canonical_link "$HOME/.agents/skills" "$LIVE_SKILLS_FARM" "$HOME/.agents/skills"
fi
group shared "$hook_count owner hooks linted · $skill_count owner skills · North-composed instructions" "$before"

# Validate a provider hook manifest. Shared adapter commands must resolve to the
# canonical source tree. North lifecycle commands must use the immutable system
# package surface; mutable checkout lifecycle bindings are never authoritative.
validate_hooks() {
  local manifest="$1" provider="$2" expected_provider="$3"
  local count=0 ev command raw_command provider_marker identity_kind first resolved expected basename declared_shared interpreter detach
  local detach hook_sha role provenance_manifest provenance_digest expected_resolved immutable_north=0
  local -A provenance_seen=()
  HOOK_PROVENANCE_SUMMARY='immutable North package commands · static declaration'
  while IFS=$'\t' read -r ev command; do
    [ -n "$command" ] || continue
    count=$((count + 1))
    raw_command="$command"
    provider_marker=''
    detach=''
    interpreter=''
    if [[ "$command" =~ ^AGENT_PROVIDER=([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
      provider_marker="${BASH_REMATCH[1]}"
      command="${BASH_REMATCH[2]}"
    fi
    if [ "$command" = '/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV /etc/codex/hooks/runtime/bash /etc/codex/hooks/north-clock-guard.sh' ]; then
      if [ -n "$provider_marker" ]; then
        bad "$provider $ev sets AGENT_PROVIDER on an unrelated hook: $raw_command"
      else
        immutable_north=1
        ok_detail "$provider $ev → immutable managed clock guard"
      fi
      continue
    fi
    if [[ "$command" =~ ^/run/current-system/sw/bin/bash[[:space:]]+(.+)$ ]]; then
      interpreter='/run/current-system/sw/bin/bash'
      command="${BASH_REMATCH[1]}"
    fi
    # hook-detach is a transparent telemetry wrapper: it drains the payload,
    # re-execs the real hook detached, and returns. The wrapped command keeps
    # the identity of the hook it carries, so unwrap before classifying — the
    # same way the exact Bash interpreter above is unwrapped.
    if [[ "$command" =~ ^/home/tom/\.agents/hooks/hook-detach\.sh[[:space:]]+(.+)$ ]]; then
      detach='hook-detach'
      command="${BASH_REMATCH[1]}"
    fi
    first="${command%% *}"
    basename="${first##*/}"
    identity_kind=''
    case "$first" in
      /run/current-system/sw/bin/north-on-spawn|/home/tom/code/north/main/bin/north-on-spawn)
        identity_kind='spawn'
        ;;
      /run/current-system/sw/bin/north-on-tooluse|/home/tom/code/north/main/bin/north-on-tooluse)
        identity_kind='repair'
        ;;
    esac
    expected="$SHARED/hooks/$basename"
    declared_shared=0
    case "$first" in
      "/home/tom/.agents/hooks/$basename"|"/home/tom/code/north/main/profiles/tom/hooks/$basename"|"$expected"|"$basename")
        declared_shared=1
        ;;
    esac
    if [ -n "$interpreter" ]; then
      ok_detail "$provider $ev uses root-managed exact Bash interpreter"
    fi
    if [ -n "$provider_marker" ] && [ -z "$identity_kind" ]; then
      bad "$provider $ev sets AGENT_PROVIDER on an unrelated hook: $raw_command"
    elif [ -n "$identity_kind" ] && [ "$provider_marker" != "$expected_provider" ]; then
      bad "$provider $ev North identity $identity_kind must set AGENT_PROVIDER=$expected_provider: $raw_command"
    elif [[ "$first" = /run/current-system/sw/bin/north-on-spawn ||
            "$first" = /run/current-system/sw/bin/north-on-tooluse ||
            "$first" = /run/current-system/sw/bin/north-mark-delegated ||
            "$first" = /run/current-system/sw/bin/north-on-stop ]]; then
      immutable_north=1
      ok_detail "$provider $ev → immutable system package command $basename"
    elif [[ "$first" = /home/tom/code/north/main/bin/* ]]; then
      bad "$provider $ev uses mutable checkout North lifecycle command $first; use /run/current-system/sw/bin/$basename"
    elif [ "$declared_shared" -eq 1 ]; then
      if [ "$LOCAL" -eq 1 ]; then
        expected_resolved="$(readlink -f "$LIVE_SHARED/hooks/$basename" 2>/dev/null || true)"
        if IFS=$'\t' read -r resolved hook_sha \
          < <(hook_target_fingerprint "$first" \
                "$LIVE_NORTH_ROOT" "$LIVE_BEAGLE_ROOT" \
                "$LIVE_FRAM_ROOT" "$LIVE_FIRN_ROOT") &&
           [ "$resolved" = "$expected_resolved" ]; then
          role="$basename:shared-adapter"
          if record_live_hook_binding "$role" "$resolved" "$hook_sha"; then
            provenance_seen["$resolved"$'\t'"$hook_sha"]=1
            ok_detail "$provider $ev → $basename · development checkout (mutable): $resolved · sha256=$hook_sha"
          else
            bad "$provider $ev split shared hook binding: $HOOK_SPLIT_REASON"
          fi
        else
          bad "$provider $ev live hook is missing/non-executable or resolves to '${resolved:-missing}', expected '$expected_resolved'"
        fi
      else
        ok_detail "$provider $ev declares canonical shared hook $basename"
      fi
    else bad "$provider $ev hook is outside the canonical composed profile: $raw_command"; fi
  done < <(jq -r '.hooks // {} | to_entries[] | .key as $event | .value[] | .hooks[]? | select(.type == "command") | [$event,.command] | @tsv' "$manifest")
  if [ "$LOCAL" -eq 1 ] && [ "${#provenance_seen[@]}" -gt 0 ]; then
    provenance_manifest="$(
      printf '%s\n' "${!provenance_seen[@]}" |
        sort
    )"
    provenance_digest="$(printf '%s\n' "$provenance_manifest" | sha256sum | awk '{print $1}')"
    if [ "$immutable_north" -eq 1 ]; then
      HOOK_PROVENANCE_SUMMARY="immutable North package commands · ${#provenance_seen[@]} mutable shared adapter targets · manifest sha256=$provenance_digest"
    else
      HOOK_PROVENANCE_SUMMARY="${#provenance_seen[@]} mutable shared adapter targets · manifest sha256=$provenance_digest"
    fi
  fi
  HOOK_BINDINGS="$count"
}

manifest_guard_count() {
  local manifest="$1" matcher_token="$2"
  jq -r --arg token "$matcher_token" '
    [.hooks.PreToolUse[]? |
     select(((.matcher // "") | split("|") | index($token)) != null) |
     .hooks[]? |
     select(.type == "command" and (.command | endswith("/agent-spawn-guard.sh")))] |
    length
  ' "$manifest"
}

require_manifest_guard_count() {
  local manifest="$1" provider="$2" matcher_token="$3" expected="$4" contract="$5" count
  count="$(manifest_guard_count "$manifest" "$matcher_token" 2>/dev/null || printf invalid)"
  if [ "$count" = "$expected" ]; then ok_detail "$provider $contract"
  else bad "$provider $contract: found $count matching guard binding(s), expected $expected"; fi
}

validate_codex_managed_policy() {
  if ! need_toml "$CODEX_REQUIREMENTS" 'Codex managed requirements'; then return; fi
  CODEX_MANAGED_BINDINGS="$(
    codex_managed_policy_binding_count "$CODEX_REQUIREMENTS" 2>/dev/null
  )" || CODEX_MANAGED_BINDINGS=''
  if [ "$CODEX_MANAGED_BINDINGS" = 19 ]; then
    ok_detail 'Codex managed-only, fail-closed, remote-control-disabled policy is the exact 19-binding authoritative contract'
  else
    bad 'Codex managed requirements differ from the authoritative hook contract'
  fi

  local module="$REPO/modules/codex/default.bnix"
  local spec relative source_expr expected_checkout authority git_blob_path
  local promoted_path live resolved
  # relative|module source expression|checkout|authority|blob path|promoted path.
  # A promoted path is the enforcement-deployment-relative name the generation's
  # tmpfiles link points at; it is empty for anything the generation still owns.
  local -a source_specs=(
    "requirements.toml|(s flakeRoot \"/modules/codex/requirements.toml\")|$CODEX_REQUIREMENTS|self|modules/codex/requirements.toml|"
    "beagle-session-start.sh|(promoted \"beagle-session-start.sh\"|$BEAGLE_INTEGRATION/hooks/beagle-session-start.sh|beagle|integrations/north/hooks/beagle-session-start.sh|beagle/integrations/north/hooks/beagle-session-start.sh"
    "agent-spawn-guard.sh|(promoted \"agent-spawn-guard.sh\"|$SHARED/hooks/agent-spawn-guard.sh|north|profiles/tom/hooks/agent-spawn-guard.sh|north/profiles/tom/hooks/agent-spawn-guard.sh"
    "code-upstream-guard.sh|(s inputs.fram \"/integrations/north/hooks/code-upstream-guard.sh\")|$FRAM_INTEGRATION/hooks/code-upstream-guard.sh|fram|integrations/north/hooks/code-upstream-guard.sh|"
    "firn-guard.sh|(s flakeRoot \"/modules/north-profile/firn/hooks/firn-guard.sh\")|$FIRN_INTEGRATION/hooks/firn-guard.sh|self|modules/north-profile/firn/hooks/firn-guard.sh|"
    "north-clock-guard.sh|(promoted \"north-clock-guard.sh\"|$SHARED/hooks/north-clock-guard.sh|north|profiles/tom/hooks/north-clock-guard.sh|north/profiles/tom/hooks/north-clock-guard.sh"
    "north-clock-guard.py|(promoted \"north-clock-guard.py\"|$SHARED/hooks/north-clock-guard.py|north|profiles/tom/hooks/north-clock-guard.py|north/profiles/tom/hooks/north-clock-guard.py"
    "tripwire-guard.sh|(promoted \"tripwire-guard.sh\"|$SHARED/hooks/tripwire-guard.sh|north|profiles/tom/hooks/tripwire-guard.sh|north/profiles/tom/hooks/tripwire-guard.sh"
    "logcompress-hook.js|(promoted \"logcompress-hook.js\"|$SHARED/hooks/logcompress-hook.js|north|profiles/tom/hooks/logcompress-hook.js|north/profiles/tom/hooks/logcompress-hook.js"
    "logcompress.js|(promoted \"logcompress.js\"|$SHARED/hooks/logcompress.js|north|profiles/tom/hooks/logcompress.js|north/profiles/tom/hooks/logcompress.js"
    "racket-build-guard.sh|(promoted \"racket-build-guard.sh\"|$BEAGLE_INTEGRATION/hooks/racket-build-guard.sh|beagle|integrations/north/hooks/racket-build-guard.sh|beagle/integrations/north/hooks/racket-build-guard.sh"
    "lib/authoring-killswitch.sh|(promoted \"lib/authoring-killswitch.sh\"|$SHARED/hooks/lib/authoring-killswitch.sh|north|profiles/tom/hooks/lib/authoring-killswitch.sh|north/profiles/tom/hooks/lib/authoring-killswitch.sh"
    "lib/harness-dial.sh|(promoted \"lib/harness-dial.sh\"|$SHARED/hooks/lib/harness-dial.sh|north|profiles/tom/hooks/lib/harness-dial.sh|north/profiles/tom/hooks/lib/harness-dial.sh"
    "registry.tsv|(promoted \"registry.tsv\"|$SHARED/hooks/registry.tsv|north|profiles/tom/hooks/registry.tsv|north/profiles/tom/hooks/registry.tsv"
    "north-on-spawn-codex|(s flakeRoot \"/dotfiles/codex/hooks/north-on-spawn-codex\")|$CODEX/hooks/north-on-spawn-codex|self|dotfiles/codex/hooks/north-on-spawn-codex|"
    "north-on-tooluse-codex|(s flakeRoot \"/dotfiles/codex/hooks/north-on-tooluse-codex\")|$CODEX/hooks/north-on-tooluse-codex|self|dotfiles/codex/hooks/north-on-tooluse-codex|"
    "north-mark-delegated-codex|(s flakeRoot \"/dotfiles/codex/hooks/north-mark-delegated-codex\")|$CODEX/hooks/north-mark-delegated-codex|self|dotfiles/codex/hooks/north-mark-delegated-codex|"
    "north-on-stop-codex|(s flakeRoot \"/dotfiles/codex/hooks/north-on-stop-codex\")|$CODEX/hooks/north-on-stop-codex|self|dotfiles/codex/hooks/north-on-stop-codex|"
    "north-clock-guard-codex|(s flakeRoot \"/dotfiles/codex/hooks/north-clock-guard-codex\")|$CODEX/hooks/north-clock-guard-codex|self|dotfiles/codex/hooks/north-clock-guard-codex|"
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
  if grep -Fq '"codex/hooks/north"' "$module" &&
     grep -Fq '{:source northPkg}' "$module" &&
     grep -Fq '(get (get inputs.north.packages pkgs.stdenv.hostPlatform.system)' "$module" &&
     grep -Fq ':default)' "$module"; then
    ok_detail 'Codex module pins the complete North hook runtime from the locked default package'
  else
    bad 'Codex module does not install the exact locked North package hook runtime'
  fi
  if grep -Fq '(get (get inputs.north.packages pkgs.stdenv.hostPlatform.system)' "$module" &&
     grep -Fq ':codex)' "$module" &&
     grep -Fq ':environment.systemPackages [codexPkg]' "$module" &&
     grep -Fq '"codex/runtime"' "$module" &&
     grep -Fq '{:source codexPkg}' "$module"; then
    ok_detail 'Firn installs inputs.north.packages.${system}.codex and exposes that exact derivation as the managed runtime marker'
  else
    bad 'Codex module must install and expose the exact inputs.north packages.${system}.codex derivation'
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
       "$wrappers/north-clock-guard-codex"; then
    ok_detail 'Codex managed lifecycle + clock adapters pass shellcheck'
  else
    bad 'Codex managed lifecycle or clock adapter fails shellcheck'
  fi
  if [ ! -f "$SHARED/hooks/north-clock-guard.py" ] && [ "$LOCAL" -eq 0 ]; then
    note "North-owned clock admission core unavailable in repository-only mode"
  elif python3 - "$SHARED/hooks/north-clock-guard.py" <<'PY'
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
PY
  then
    ok_detail 'Provider-neutral clock admission core compiles as Python'
  else
    bad 'Provider-neutral clock admission core fails Python compilation'
  fi

  if [ "$LOCAL" -eq 1 ]; then
    local generation_exact=1
    local north_revision beagle_revision fram_revision source_repo source_revision
    local immutable_source
    if cmp -s "$CODEX_REQUIREMENTS" /etc/codex/requirements.toml; then :
    else
      generation_exact=0
      bad 'Codex managed requirements are not the current /etc generation'
    fi
    # North and Beagle enforcement is attested against the active promote record;
    # everything else is still attested against the flake pin that built it.
    north_revision="$(promote_record_revision north 2>/dev/null || true)"
    beagle_revision="$(promote_record_revision beagle 2>/dev/null || true)"
    fram_revision="$(flake_locked_revision "$REPO/flake.lock" fram 2>/dev/null || true)"
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
        fram)
          source_repo="$(git -C "$(dirname "$expected_checkout")" \
            rev-parse --show-toplevel 2>/dev/null || true)"
          source_revision="$fram_revision"
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
        bad "Codex managed hook $live is not exact to flake.lock $authority@${source_revision:-missing}:$git_blob_path"
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
    if [ -n "$resolved" ] && [[ "$resolved" = /nix/store/* ]]; then :
    else
      generation_exact=0
      bad 'Codex pinned North hook runtime is missing or not store-backed'
    fi
    local interactive_codex managed_codex
    interactive_codex="$(command -v codex 2>/dev/null || true)"
    managed_codex="$(readlink -f /etc/codex/runtime/bin/codex 2>/dev/null || true)"
    interactive_codex="$(readlink -f "$interactive_codex" 2>/dev/null || true)"
    if [ -n "$managed_codex" ] && [[ "$managed_codex" = /nix/store/* ]] &&
       [ -x "$managed_codex" ]; then
      ok_detail 'North managed Codex is an exact immutable executable'
    else
      generation_exact=0
      bad 'North managed Codex runtime marker is missing, mutable, or non-executable'
    fi
    if [ -n "$interactive_codex" ] && [ "$interactive_codex" = "$managed_codex" ]; then
      ok_detail 'Interactive Codex directly resolves to the managed provider executable'
    elif [ -n "$interactive_codex" ]; then
      ok_detail 'Interactive Codex uses a distinct user launcher; managed provider authority remains the immutable runtime marker'
    else
      soft 'Interactive Codex is absent from PATH; managed provider authority remains independently attested'
    fi
    # The lifecycle runtimes are executed out of the North package, which supplies
    # their interpreter PATH and NORTH_HOME, so they remain pinned by flake.lock
    # even though their bodies also ride the promoted payload.
    local locked_north_revision
    locked_north_revision="$(flake_locked_revision "$REPO/flake.lock" north 2>/dev/null || true)"
    for relative in \
      bin/north-on-spawn \
      bin/north-on-tooluse \
      bin/north-mark-delegated \
      bin/north-on-stop; do
      if [ -n "$locked_north_revision" ] &&
         north_wrapped_runtime_matches_locked_source \
           "/etc/codex/hooks/north/$relative" "$HOME/code/north/main" \
           "$locked_north_revision" "$relative"; then :
      else
        generation_exact=0
        bad "Codex North runtime $relative is not an exact locked body with immutable package-wrapper provenance at ${locked_north_revision:-missing}"
      fi
    done
    if [ "$generation_exact" -eq 1 ]; then
      CODEX_HOOK_PROVENANCE='sealed promoted enforcement · immutable /nix/store generation · exact Firn sources'
      ok_detail 'Codex authoritative hook set is exact: sealed promoted enforcement over an immutable generation'
    else
      CODEX_HOOK_PROVENANCE='generation drift detected'
    fi
  else
    CODEX_HOOK_PROVENANCE='immutable /nix/store generation deferred to --local'
  fi
}

before=$fail
claude_north='connection deferred to --local'
claude_north_topology='explicit corpus env deferred'
claude_fram='connection deferred to --local'
claude_fram_topology='topology deferred'
claude_linear='connection deferred to --local'
claude_orchestration='cache freshness deferred to --local'
need_json "$CLAUDE/settings.json" 'Claude settings'
if grep -Fq '(pkgs.writeText "claude-settings.json"' \
     "$REPO/modules/claude/default.bnix" &&
   grep -Fq ':home.activation.seedClaudeSettings' \
     "$REPO/modules/claude/default.bnix" &&
   grep -Fq '(config.lib.dag.entryAfter ["writeBoundary"]' \
     "$REPO/modules/claude/default.bnix" &&
   ! rg -q 'linkClaudeSettings|/code/nixos-config/dotfiles/claude/settings\.json' \
     "$REPO/modules/claude/default.bnix" "$REPO/modules/claude/default.nix"; then
  ok_detail 'Claude settings are atomically reseeded from each committed generation into writable state'
else
  bad 'Claude settings delivery must atomically reseed from the committed generation without a checkout link'
fi
if command -v shellcheck >/dev/null 2>&1 && shellcheck -S warning "$CLAUDE/statusline.sh"; then
  ok_detail "Claude statusline shellcheck"
else bad "Claude statusline shellcheck failed"; fi
if jq -e '.statusLine.type == "command" and .statusLine.command == "bash \"$HOME/code/nixos-config/dotfiles/claude/statusline.sh\""' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail "Claude statusline points at canonical adapter"
else bad "Claude statusline is not wired to $CLAUDE/statusline.sh"; fi
if bash "$CLAUDE/statusline.test.sh" >/dev/null; then
  ok_detail "Claude statusline observer is detached and output-safe"
else bad "Claude statusline observer test failed"; fi
if grep -Fqx '  local north="/run/current-system/sw/bin/north"' "$CLAUDE/statusline.sh" &&
   ! grep -Fq '/home/tom/code/north/main/bin/' "$CLAUDE/statusline.sh"; then
  ok_detail "Claude statusline observer uses the immutable North package command"
else bad "Claude statusline observer must use /run/current-system/sw/bin/north"; fi
if [ ! -f "$SHARED/hooks/north-session-end.sh" ] && [ "$LOCAL" -eq 0 ]; then
  note "North-owned SessionEnd hook unavailable in repository-only mode"
elif jq -e '
     .hooks.SessionEnd[0].hooks[0].command
       == "/home/tom/.agents/hooks/north-session-end.sh"
   ' "$CLAUDE/settings.json" >/dev/null &&
   ! grep -Fq 'northSessionEnd' "$REPO/modules/claude/default.bnix" &&
   ! grep -Fq 'writeShellScriptBin "north-session-end"' "$REPO/modules/claude/default.bnix" &&
   grep -Fqx 'CONCERN="/run/current-system/sw/bin/concern"' "$SHARED/hooks/north-session-end.sh" &&
   grep -Fq 'timeout 5 /run/current-system/sw/bin/north-stream-sync' "$SHARED/hooks/north-session-end.sh" &&
   ! grep -Fq '/home/tom/code/north/main/bin/' "$SHARED/hooks/north-session-end.sh"; then
  ok_detail "Claude SessionEnd is profile-owned and calls immutable North package commands"
else bad "Claude SessionEnd must use the composed profile hook with immutable North commands"; fi
if [ ! -f "$BEAGLE_INTEGRATION/hooks/beagle-session-start.test.sh" ] &&
   [ "$LOCAL" -eq 0 ]; then
  note "Beagle-owned SessionStart lifecycle test unavailable in repository-only mode"
elif bash "$BEAGLE_INTEGRATION/hooks/beagle-session-start.test.sh" >/dev/null; then
  ok_detail "Beagle SessionStart gates its immutable Fram status probe behind project detection"
else bad "Beagle SessionStart lifecycle test failed"; fi
if command -v shellcheck >/dev/null 2>&1 && \
   shellcheck -S warning "$LAUNCHER_BIN/claude" "$LAUNCHER_BIN/codex" "$LAUNCHER_BIN/launcher.test.sh"; then
  ok_detail "Account launcher wrappers shellcheck"
else bad "Account launcher wrappers shellcheck failed"; fi
if bash "$LAUNCHER_BIN/launcher.test.sh" >/dev/null; then
  ok_detail "Account launcher fallbacks are diagnostic (missing/nonzero/empty/malformed north, no-eligible, absent dir, clean pick)"
else bad "Account launcher diagnostics test failed"; fi
if command -v shellcheck >/dev/null 2>&1 && \
   shellcheck -S warning "$LAUNCHER_BIN/north-enforcement-promote" \
     "$LAUNCHER_BIN/north-enforcement-promote.test.sh"; then
  ok_detail "Enforcement promote command shellchecks"
else bad "Enforcement promote command shellcheck failed"; fi
if bash "$LAUNCHER_BIN/north-enforcement-promote.test.sh" >/dev/null; then
  ok_detail "Enforcement promote seals, attests, retains previous, and rolls back"
else bad "Enforcement promote transaction test failed"; fi
if grep -Fq '{:source (s flakeRoot "/dotfiles/bin")}' "$REPO/modules/bash/default.bnix" &&
   ! grep -Fq 'code/nixos-config/dotfiles/bin' "$REPO/modules/bash/default.bnix"; then
  ok_detail "Account launcher directory is generation-owned store content"
else bad "Account launcher directory must use the store-backed flake source"; fi
if [ "$LOCAL" -eq 1 ]; then
  live_safe_push="$(command -v safe-push 2>/dev/null || true)"
  live_safe_push_resolved="$(readlink -f "$live_safe_push" 2>/dev/null || true)"
  if [ -x "$live_safe_push" ] && [[ "$live_safe_push_resolved" = /nix/store/* ]] &&
     "$live_safe_push" --help | grep -Fq -- '--to BRANCH'; then
    ok_detail "Live safe-push is immutable and supports explicit --to destinations"
  else
    bad "Live safe-push must resolve into /nix/store and expose --to BRANCH"
  fi
fi
if jq -e '.autoMemoryEnabled == false' "$CLAUDE/settings.json" >/dev/null; then ok_detail "auto-memory disabled"
else bad "Claude autoMemoryEnabled must be false"; fi
if jq -e '
  .enabledPlugins["orchestration@orchestration"] == true
  and .extraKnownMarketplaces.orchestration.source == {
    "source": "directory",
    "path": "/home/tom/code/north/main/orchestration"
  }
' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail "Orchestration plugin resolves to the in-tree north/orchestration marketplace"
else
  bad "Claude Orchestration plugin must be enabled from /home/tom/code/north/main/orchestration"
fi
if [ -f "$HOME/code/north/main/orchestration/.claude-plugin/marketplace.json" ] &&
   [ -f "$HOME/code/north/main/orchestration/.claude-plugin/plugin.json" ]; then
  ok_detail "in-tree Orchestration marketplace + plugin manifests present"
else
  bad "north/orchestration must carry .claude-plugin/marketplace.json and plugin.json"
fi
validate_hooks "$CLAUDE/settings.json" Claude anthropic
# The billable clock guard was removed from CLAUDE hooks on tom order (659ed26,
# billing clock demoted to an opt-in knob), so ZERO bindings is the expected
# state and this must not demand two. The property still worth enforcing is
# conditional: any binding that DOES exist must go through the immutable
# /etc/codex runtime rather than a mutable user path. The Codex-side guard
# checks are unaffected -- that removal was Claude-only.
if jq -e '
  [
    .hooks.PreToolUse[]?.hooks[]?
    | select(
        .type == "command"
        and (.command | endswith("/north-clock-guard.sh"))
      )
    | .command
  ] as $commands
  | all(
      $commands[];
      . == "/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV /etc/codex/hooks/runtime/bash /etc/codex/hooks/north-clock-guard.sh"
    )
' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail 'every bound Claude clock guard uses the immutable managed runtime'
else
  bad 'a bound Claude clock guard must use the immutable /etc/codex managed runtime'
fi
require_manifest_guard_count "$CLAUDE/settings.json" Claude Bash 1 'user Bash topology guard is bound once'
claude_bindings="$HOOK_BINDINGS"
claude_hook_provenance="$HOOK_PROVENANCE_SUMMARY"
if [ "$LOCAL" -eq 1 ]; then
  writable_claude_settings_match_control_plane \
    "$HOME/.claude/settings.json" "$CLAUDE/settings.json" \
    "$HOME/.claude/settings.json"
  canonical_link "$HOME/.claude/skills" "$LIVE_SKILLS_FARM" "$HOME/.claude/skills"
  canonical_link "$HOME/.claude/hooks" "$LIVE_SHARED/hooks" "$HOME/.claude/hooks"
  canonical_link "$HOME/.claude/CLAUDE.md" "$LIVE_SHARED/AGENTS.md" "$HOME/.claude/CLAUDE.md"
  canonical_link "$HOME/.claude/commands" "$LIVE_CLAUDE/commands" "$HOME/.claude/commands"
  if [ -f "$HOME/.claude.json" ]; then
    for server in fram north linear-mcp-msa-new; do
      jq -e --arg s "$server" '.mcpServers[$s]' "$HOME/.claude.json" >/dev/null || bad "Claude user MCP '$server' is missing"
    done
    extra="$(jq -r '.mcpServers | keys[] | select(. != "fram" and . != "north" and . != "linear-mcp-msa-new")' "$HOME/.claude.json")"
    [ -z "$extra" ] || bad "unexpected Claude user MCP server(s): ${extra//$'\n'/, }"
    fram_log="$(jq -r '.mcpServers.fram.env.FRAM_LOG // empty' "$HOME/.claude.json")"
    fram_telemetry_log="$(jq -r '.mcpServers.fram.env.FRAM_TELEMETRY_LOG // empty' "$HOME/.claude.json")"
    fram_threads="$(jq -r '.mcpServers.fram.env.FRAM_THREADS // empty' "$HOME/.claude.json")"
    [ "$fram_log" = "$CANONICAL_FRAM_LOG" ] || bad "Claude Fram FRAM_LOG is '${fram_log:-unset}', expected '$CANONICAL_FRAM_LOG'"
    [ "$fram_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ] || bad "Claude Fram FRAM_TELEMETRY_LOG is '${fram_telemetry_log:-unset}', expected '$CANONICAL_FRAM_TELEMETRY_LOG'"
    [ "$fram_threads" = "$CANONICAL_FRAM_THREADS" ] || bad "Claude Fram FRAM_THREADS is '${fram_threads:-unset}', expected '$CANONICAL_FRAM_THREADS'"
    if [ "$fram_log" = "$CANONICAL_FRAM_LOG" ] &&
       [ "$fram_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ] &&
       [ "$fram_threads" = "$CANONICAL_FRAM_THREADS" ]; then
      claude_fram_topology='canonical split corpus'
    else
      claude_fram_topology='stale corpus configuration'
    fi
    north_log="$(jq -r '.mcpServers.north.env.FRAM_LOG // empty' "$HOME/.claude.json")"
    north_telemetry_log="$(jq -r '.mcpServers.north.env.FRAM_TELEMETRY_LOG // empty' "$HOME/.claude.json")"
    north_threads="$(jq -r '.mcpServers.north.env.FRAM_THREADS // empty' "$HOME/.claude.json")"
    north_port="$(jq -r '.mcpServers.north.env.NORTH_PORT // empty' "$HOME/.claude.json")"
    [ "$north_log" = "$CANONICAL_FRAM_LOG" ] || bad "Claude North FRAM_LOG is '${north_log:-unset}', expected '$CANONICAL_FRAM_LOG'"
    [ "$north_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ] || bad "Claude North FRAM_TELEMETRY_LOG is '${north_telemetry_log:-unset}', expected '$CANONICAL_FRAM_TELEMETRY_LOG'"
    [ "$north_threads" = "$CANONICAL_FRAM_THREADS" ] || bad "Claude North FRAM_THREADS is '${north_threads:-unset}', expected '$CANONICAL_FRAM_THREADS'"
    [ "$north_port" = 7977 ] || bad "Claude North NORTH_PORT is '${north_port:-unset}', expected '7977'"
    if [ "$north_log" = "$CANONICAL_FRAM_LOG" ] &&
       [ "$north_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ] &&
       [ "$north_threads" = "$CANONICAL_FRAM_THREADS" ] &&
       [ "$north_port" = 7977 ]; then
      claude_north_topology='canonical explicit instance env'
    else
      claude_north_topology='stale/missing instance env'
    fi
    project_count="$(jq '[.projects[]? | select(.mcpServers != null)] | length' "$HOME/.claude.json")"
    note "$project_count project-scoped Claude MCP registrations (allowed)"
    ok_detail "Claude MCP declarations: North + canonical split Fram corpus + Linear"
  else bad "$HOME/.claude.json is missing"; fi
  if claude_probe_binary_is_authoritative; then
    if [ -n "${CLAUDE_BIN:-}" ]; then
      ok_detail "Claude health probe uses explicit test override $CLAUDE_BIN"
    else
      ok_detail "Claude health probe uses immutable /run/current-system/sw/bin/claude with default user state"
    fi
    claude_mcp_status=0
    claude_mcp_output="$(
      run_claude_probe "${MCP_PROBE_TIMEOUT_SECONDS:-20}" mcp list 2>&1
    )" || claude_mcp_status=$?
    if [ "$claude_mcp_status" -eq 0 ]; then
      claude_mcp_exact=1
      for server in north fram; do
        claude_mcp_server_connected "$claude_mcp_output" "$server" || {
          claude_mcp_exact=0
          bad "Claude MCP '$server' is missing or not connected:\n$claude_mcp_output"
        }
      done
      for server in "${CLIENT_SCOPED_MCP_SERVERS[@]}"; do
        if claude_mcp_server_connected "$claude_mcp_output" "$server"; then
          claude_linear='connected'
        else
          claude_linear='unauthenticated (advisory — client-scoped)'
          soft "client MCP '$server': unauthenticated (advisory — client-scoped)"
        fi
      done
      if [ "$claude_mcp_exact" -eq 1 ]; then
        claude_north="connected; $claude_north_topology"
        claude_fram="connected; $claude_fram_topology"
        ok_detail "Claude reports North + Fram MCP connected"
      fi
    elif [ "$claude_mcp_status" -eq 124 ]; then
      bad "Claude MCP health probe timed out after ${MCP_PROBE_TIMEOUT_SECONDS:-20}s; its process group was reaped"
    else
      bad "claude rejected its config while checking MCP health (exit $claude_mcp_status):\n$claude_mcp_output"
    fi
    # Orchestration ships INSIDE north (nixos-config 57b0521), so there is no
    # separate flake input to pin and no detached marketplace checkout to
    # verify. The plugin is read straight from the north working tree, the
    # same way every other agent-config surface is symlinked from a repo, so
    # exact-revision drift is not a thing that can happen here any more.
    claude_orchestration='in-tree (north/orchestration)'
  else bad "Claude health probe binary is missing, non-executable, or not the immutable /run/current-system/sw/bin/claude"; fi
fi
provider_group Claude "$before" \
  "Hooks       $claude_bindings bindings" \
  'Identity    adapter-pinned native spawn + repair → anthropic' \
  'Topology    user Bash hook (loaded directly by Claude)' \
  "Hook source $claude_hook_provenance" \
  "Bootstrap   static config parsed · Orchestration $claude_orchestration" \
  "MCP         North: $claude_north" \
  "            Fram: $claude_fram" \
  "            Linear: $claude_linear"

before=$fail
note_ignored_codex_legacy_manifest "$CODEX_LEGACY_HOOKS"
need_toml "$CODEX/config.toml" 'Codex config'
if grep -Fq '{:source (s flakeRoot "/dotfiles/codex/config.toml")}' \
     "$REPO/modules/codex/default.bnix" &&
   grep -Fq '{:source (s flakeRoot "/dotfiles/codex/hooks.json")}' \
     "$REPO/modules/codex/default.bnix" &&
   grep -Fq '".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";' \
     "$REPO/modules/codex/default.nix" &&
   grep -Fq '".codex/hooks.json".source = "${flakeRoot}/dotfiles/codex/hooks.json";' \
     "$REPO/modules/codex/default.nix" &&
   ! rg -q 'code/nixos-config/dotfiles/codex/(config\.toml|hooks\.json)' \
     "$REPO/modules/codex/default.bnix" "$REPO/modules/codex/default.nix"; then
  ok_detail 'Codex config and legacy hook state are generation-owned store sources'
else
  bad 'Codex config and legacy hook state must use the committed flake sources'
fi
validate_codex_managed_policy
codex_bindings="${CODEX_MANAGED_BINDINGS:-invalid}"
codex_hook_provenance="${CODEX_HOOK_PROVENANCE:-declaration drift detected}"
ok_detail 'Codex legacy ~/.codex/hooks.json is intentionally ignored; it contributes zero active bindings'
codex_north='declared; canonical explicit instance env; live probe deferred'
codex_fram='declared; canonical split corpus; live probe deferred'
codex_linear='authentication deferred to an interactive credential check'
grep -q '^\[mcp_servers\.north\]' "$CODEX/config.toml" || bad "Codex config does not declare North MCP"
grep -q '^\[mcp_servers\.fram\]' "$CODEX/config.toml" || bad "Codex config does not declare Fram MCP"
grep -q '^\[mcp_servers\.linear-mcp-msa-new\]' "$CODEX/config.toml" || bad "Codex config does not declare Linear MCP"
if codex_mcp_command_error="$(codex_mcp_commands_are_immutable "$CODEX/config.toml" 2>&1)"; then
  ok_detail "Codex North + Fram MCP commands use immutable system-generation executables"
else
  codex_north='declared; mutable command drift detected'
  codex_fram='declared; mutable command drift detected'
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
codex_fram_paths="$(python3 -c 'import sys,tomllib; c=tomllib.load(open(sys.argv[1],"rb")); e=c.get("mcp_servers",{}).get("fram",{}).get("env",{}); print(e.get("FRAM_LOG","")); print(e.get("FRAM_TELEMETRY_LOG","")); print(e.get("FRAM_THREADS",""))' "$CODEX/config.toml" 2>/dev/null || true)"
codex_fram_log="$(sed -n '1p' <<<"$codex_fram_paths")"
codex_fram_telemetry_log="$(sed -n '2p' <<<"$codex_fram_paths")"
codex_fram_threads="$(sed -n '3p' <<<"$codex_fram_paths")"
[ "$codex_fram_log" = "$CANONICAL_FRAM_LOG" ] || bad "Codex Fram FRAM_LOG is '${codex_fram_log:-unset}', expected '$CANONICAL_FRAM_LOG'"
[ "$codex_fram_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ] || bad "Codex Fram FRAM_TELEMETRY_LOG is '${codex_fram_telemetry_log:-unset}', expected '$CANONICAL_FRAM_TELEMETRY_LOG'"
[ "$codex_fram_threads" = "$CANONICAL_FRAM_THREADS" ] || bad "Codex Fram FRAM_THREADS is '${codex_fram_threads:-unset}', expected '$CANONICAL_FRAM_THREADS'"
if [ "$LOCAL" -eq 1 ]; then
  immutable_store_link_matches \
    "$HOME/.codex/config.toml" "$CODEX/config.toml" "$HOME/.codex/config.toml"
  immutable_store_link_matches \
    "$HOME/.codex/hooks.json" "$CODEX/hooks.json" "$HOME/.codex/hooks.json"
  canonical_link "$HOME/.codex/AGENTS.md" "$LIVE_SHARED/AGENTS.md" "$HOME/.codex/AGENTS.md"
  if command -v codex >/dev/null 2>&1; then
    codex_mcp_status=0
    mcp_output="$(
      CODEX_HOME="$HOME/.codex" \
      CODEX_SQLITE_HOME="$HOME/.codex/sqlite" \
        run_codex_mcp_inventory "${MCP_PROBE_TIMEOUT_SECONDS:-20}" 2>&1
    )" || codex_mcp_status=$?
    if [ "$codex_mcp_status" -eq 0 ]; then
      codex_inventory_ok=1
      for server in north fram; do
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
        ok_detail "Codex config parsed; North + Fram enabled; Linear OAuth excluded from the noninteractive inventory"
        if [ "$codex_north_env_ok" -eq 1 ]; then
          codex_north='enabled; canonical explicit instance env'
        else
          codex_north='enabled; explicit instance env drift detected'
        fi
        codex_fram='enabled; canonical split corpus'
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
  'Legacy      ~/.codex/hooks.json ignored by managed-only policy (0 active bindings)' \
  'Identity    managed lanes harness-owned · pinned native fallback → openai' \
  'Topology    sole policy: managed /etc/codex/hooks' \
  "Hook source $codex_hook_provenance" \
  'Bootstrap   static config parsed' \
  "MCP         North: $codex_north" \
  "            Fram: $codex_fram" \
  "            Linear: $codex_linear"

# Hermes — controller host over the North MCP. The static surface (config,
# plugin manifest, fail-closed adapter, and firn module) is asserted here; live
# symlink resolution is deferred to --local.
before=$fail
hermes_plugin='north-bridge (fail-closed guard + North lifecycle)'
hermes_mcp='declared; canonical packaged North MCP + state env; live probe deferred'
hermes_delegation='native delegate_task disabled (delegation toolset off)'
hermes_adapter='fail-closed contract deferred'
hermes_link='symlink resolution deferred to --local'
need_yaml "$HERMES/config.yaml" 'Hermes controller config'
# Structural assertions (parser-free): the config is small and firn-owned, so
# canonical lines are unambiguous. Mirrors the codex grep-based MCP checks.
grep -qE '^\s*-\s*north-bridge\s*$' "$HERMES/config.yaml" ||
  bad 'Hermes config must enable the north-bridge plugin (plugins.enabled)'
grep -qE '^\s*-\s*delegation\s*$' "$HERMES/config.yaml" ||
  bad 'Hermes config must disable native delegation (agent.disabled_toolsets: - delegation)'
grep -qE '^\s*command:\s*/run/current-system/sw/bin/north-mcp-packaged\s*$' "$HERMES/config.yaml" ||
  bad 'Hermes North MCP command must be the absolute packaged path /run/current-system/sw/bin/north-mcp-packaged'
grep -qE '^\s*connect_timeout:\s*[0-9]+\s*$' "$HERMES/config.yaml" ||
  bad 'Hermes North MCP must set connect_timeout (Hermes MCP schema key)'
if grep -qE '^\s*startup_timeout_sec:' "$HERMES/config.yaml"; then
  bad 'Hermes config must not use startup_timeout_sec (Codex-ism, not a Hermes MCP key)'
fi
# No provider/auth surface may leak into the controller config.
if grep -qiE '^\s*(api_key|provider|auth_mode|base_url|OPENROUTER_API_KEY|ANTHROPIC_API_KEY|OPENAI_API_KEY|NOUS_API_KEY|token)\s*:' "$HERMES/config.yaml"; then
  bad 'Hermes controller config must carry NO provider/auth/credential keys'
fi
grep -qE '^\s*NORTH_PORT:\s*"?7977"?\s*$' "$HERMES/config.yaml" ||
  bad 'Hermes North MCP NORTH_PORT must be 7977'
grep -qF "FRAM_LOG: $CANONICAL_FRAM_LOG" "$HERMES/config.yaml" ||
  bad "Hermes North FRAM_LOG must be $CANONICAL_FRAM_LOG"
grep -qF "FRAM_TELEMETRY_LOG: $CANONICAL_FRAM_TELEMETRY_LOG" "$HERMES/config.yaml" ||
  bad "Hermes North FRAM_TELEMETRY_LOG must be $CANONICAL_FRAM_TELEMETRY_LOG"
grep -qF "FRAM_THREADS: $CANONICAL_FRAM_THREADS" "$HERMES/config.yaml" ||
  bad "Hermes North FRAM_THREADS must be $CANONICAL_FRAM_THREADS"
if grep -qE '^\s*-\s*~/\.agents/skills\s*$' "$HERMES/config.yaml"; then
  ok_detail 'Hermes shares provider-neutral ~/.agents/skills'
else
  bad 'Hermes config must share external skills ~/.agents/skills'
fi
# Source-code validation — parse through Hermes' OWN config loader, not just a
# generic YAML parser. HERMES_VENV_PYTHON (or a hermes venv python discoverable
# via HERMES_CONFIG_VALIDATOR) must be able to import hermes_cli.config and load
# the file with every canonical value preserved. Deferred (structural checks
# carry the load) when no Hermes venv is available (minimal CI / cross-eval).
hermes_config='structural checks only (Hermes loader deferred)'
hermes_validator="${HERMES_VENV_PYTHON:-${HERMES_CONFIG_VALIDATOR:-}}"
if [ -n "$hermes_validator" ] && [ -x "$hermes_validator" ]; then
  if "$hermes_validator" - "$HERMES/config.yaml" <<'PYEOF' >/dev/null 2>&1
import os, sys, tempfile, shutil
src = sys.argv[1]
home = tempfile.mkdtemp()
shutil.copy(src, os.path.join(home, "config.yaml"))
os.environ["HERMES_HOME"] = home
from hermes_cli.config import load_config
cfg = load_config()
mcp = (cfg.get("mcp_servers") or {}).get("north") or {}
assert mcp.get("command") == "/run/current-system/sw/bin/north-mcp-packaged", mcp
assert int(mcp.get("connect_timeout")) == 15, mcp
assert (mcp.get("env") or {}).get("NORTH_PORT") == "7977", mcp
assert "north-bridge" in (cfg.get("plugins") or {}).get("enabled", []), cfg.get("plugins")
assert "delegation" in (cfg.get("agent") or {}).get("disabled_toolsets", []), cfg.get("agent")
assert any("agents/skills" in d for d in (cfg.get("skills") or {}).get("external_dirs", [])), cfg.get("skills")
PYEOF
  then
    hermes_config='validated through hermes_cli.config.load_config (values preserved)'
    ok_detail 'Hermes config validated by the pinned Hermes loader (hermes_cli.config)'
  else
    hermes_config='REJECTED by hermes_cli.config.load_config'
    bad 'Hermes config failed validation through the pinned Hermes loader (hermes_cli.config)'
  fi
fi
# Plugin manifest + fail-closed adapter.
if [ -f "$HERMES_BRIDGE/plugin.yaml" ]; then
  need_yaml "$HERMES_BRIDGE/plugin.yaml" 'Hermes north-bridge manifest'
  # The controller adapter must register the guard hook AND every lifecycle
  # seam it maps: mail-context capture (post_tool_call), additionalContext
  # injection (transform_tool_result / pre_llm_call), and the north-on-stop
  # keep-going decision (pre_verify).
  for hook in pre_tool_call post_tool_call transform_tool_result \
              pre_llm_call pre_verify on_session_start on_session_end; do
    grep -qE "^\s*-\s*$hook\s*$" "$HERMES_BRIDGE/plugin.yaml" ||
      bad "north-bridge manifest must register the $hook hook"
  done
else
  bad "north-bridge plugin manifest is missing: $HERMES_BRIDGE/plugin.yaml"
fi
# Hermes is a controller HOST, not a North provider: the adapter must NEVER
# stamp AGENT_PROVIDER=hermes, so North records the provider unobserved.
# Match a real assignment ("AGENT_PROVIDER": "hermes" / ["AGENT_PROVIDER"] =
# "hermes"), not prose in a docstring that names the anti-pattern.
if [ -f "$HERMES_BRIDGE/__init__.py" ] &&
   grep -qE '"AGENT_PROVIDER"[^#]*"hermes"' "$HERMES_BRIDGE/__init__.py"; then
  bad 'north-bridge must not set AGENT_PROVIDER=hermes (provider stays unobserved)'
fi
if [ -f "$HERMES_BRIDGE/__init__.py" ]; then
  if command -v python3 >/dev/null 2>&1; then
    if adapter_output="$(python3 "$HERMES_BRIDGE/north-bridge.test.py" 2>&1)"; then
      hermes_adapter='fail-closed deny + unavailable + lifecycle proven'
      ok_detail 'north-bridge adapter tests pass (fail-closed guard, unavailable, delegation, lifecycle)'
    else
      hermes_adapter='fail-closed contract BROKEN'
      bad "north-bridge adapter tests failed — fail-closed enforcement may be broken:\n$adapter_output"
    fi
  else
    bad 'python3 is required to prove the north-bridge fail-closed contract'
  fi
else
  bad "north-bridge adapter implementation is missing: $HERMES_BRIDGE/__init__.py"
fi
# Firn module: pinned upstream package + materialised controller surface.
HERMES_PINNED_REV='244dabbd9c4b542bf5c1ad0159af512c2b5d6e08'
if [ -f "$HERMES_MODULE" ]; then
  grep -q 'inputs.hermes-agent.packages' "$HERMES_MODULE" ||
    bad 'Hermes module must install the pinned upstream inputs.hermes-agent package'
  # The input URL must pin the exact reviewed MIT commit, not a floating branch.
  grep -qF "\"github:NousResearch/hermes-agent/$HERMES_PINNED_REV\"" "$HERMES_MODULE" ||
    bad "Hermes module must pin hermes-agent to the reviewed commit $HERMES_PINNED_REV"
  # Lifecycle must drive the WRAPPED North package bin, never the source checkout.
  grep -q 'inputs.north.packages' "$HERMES_MODULE" ||
    bad 'Hermes module must resolve lifecycle scripts from inputs.north.packages.${system}.default'
  if grep -qF '(s inputs.north "/bin")' "$HERMES_MODULE"; then
    bad 'Hermes lifecycle dir must use the packaged North default/bin, not the raw inputs.north source'
  fi
  grep -q 'NORTH_HERMES_LIFECYCLE_DIR' "$HERMES_MODULE" ||
    bad 'Hermes module must set NORTH_HERMES_LIFECYCLE_DIR for the bridge'
  for want in '.hermes/config.yaml' '.hermes/SOUL.md' '.hermes/plugins/north-bridge'; do
    grep -q "\"$want\"" "$HERMES_MODULE" ||
      bad "Hermes module does not materialise $want"
  done
else
  bad "Hermes firn module is missing: $HERMES_MODULE"
fi
# flake.lock must record the exact reviewed hermes-agent revision.
hermes_locked_rev="$(
  jq -er '.nodes["hermes-agent"].locked.rev | select(test("^[0-9a-f]{40}$"))' \
    "$REPO/flake.lock" 2>/dev/null || true
)"
if [ "$hermes_locked_rev" = "$HERMES_PINNED_REV" ]; then
  ok_detail "flake.lock pins hermes-agent to the reviewed commit ${HERMES_PINNED_REV:0:12}"
else
  bad "flake.lock hermes-agent rev is '${hermes_locked_rev:-missing}', expected $HERMES_PINNED_REV"
fi
if [ "$LOCAL" -eq 1 ]; then
  canonical_link "$HOME/.hermes/config.yaml" "$LIVE_HERMES/config.yaml" "$HOME/.hermes/config.yaml"
  canonical_link "$HOME/.hermes/SOUL.md" "$LIVE_SHARED/AGENTS.md" "$HOME/.hermes/SOUL.md"
  # The plugin is an IMMUTABLE nix-store source (so imports cannot write
  # __pycache__ into dotfiles) — assert it resolves into /nix/store, not the
  # mutable working tree.
  hermes_plugin_target="$(readlink -f "$HOME/.hermes/plugins/north-bridge" 2>/dev/null || true)"
  case "$hermes_plugin_target" in
    /nix/store/*) ok_detail 'Hermes north-bridge plugin is an immutable nix-store source' ;;
    *) bad "Hermes north-bridge plugin must resolve into /nix/store (immutable), got: ${hermes_plugin_target:-<unresolved>}" ;;
  esac
  if command -v hermes >/dev/null 2>&1; then
    hermes_link='config, constitution, and north-bridge symlinks resolve; hermes on PATH'
  else
    hermes_link='config/constitution/plugin symlinks resolve; hermes CLI missing from PATH'
    bad 'hermes CLI is missing from PATH'
  fi
fi
provider_group Hermes "$before" \
  "Package     pinned upstream NousResearch/hermes-agent (minimal)" \
  "Plugin      $hermes_plugin" \
  "Delegation  $hermes_delegation" \
  "Adapter     $hermes_adapter" \
  "Config      $hermes_config" \
  "MCP         North: $hermes_mcp" \
  "Skills      shared ~/.agents/skills · constitution ~/.hermes/SOUL.md" \
  "Link        $hermes_link"

before=$fail
north_coord_runtime='live probe deferred'
north_coord_ok=0
if [ "$LOCAL" -eq 1 ]; then
  if command -v systemctl >/dev/null 2>&1 && NORTH_COORD_UNIT="$(resolve_north_coord_unit)"; then
    north_coord_env="$(systemctl show "$NORTH_COORD_UNIT" -p Environment --value 2>/dev/null || true)"
    north_coord_exec="$(systemctl show "$NORTH_COORD_UNIT" -p ExecStart --value 2>/dev/null || true)"
    north_coord_pid="$(systemctl show "$NORTH_COORD_UNIT" -p MainPID --value 2>/dev/null || true)"
    north_coord_ok=1
    systemd_environment_has "$north_coord_env" "FRAM_TELEMETRY_LOG=$CANONICAL_FRAM_TELEMETRY_LOG" || {
      north_coord_ok=0
      bad "north-coord lacks canonical FRAM_TELEMETRY_LOG in its live environment"
    }
    systemd_environment_has "$north_coord_env" 'FRAM_REQUIRE_LOG_FENCE=1' || {
      north_coord_ok=0
      bad "north-coord lacks FRAM_REQUIRE_LOG_FENCE=1 in its live environment"
    }
    if classify_north_coord_exec "$north_coord_exec"; then
      ok_detail "north-coord executes the system-owned runtime selector: $NORTH_COORD_EXEC_PATH"
    elif [ "$NORTH_COORD_EXEC_KIND" = direct-checkout ]; then
      north_coord_ok=0
      bad "north-coord directly executes a checkout and bypasses the system-owned selector: $NORTH_COORD_EXEC_PATH"
    elif [ "$NORTH_COORD_EXEC_KIND" = direct-package ]; then
      north_coord_ok=0
      bad "north-coord directly executes a pinned package and bypasses runtime promotion: $NORTH_COORD_EXEC_PATH"
    else
      north_coord_ok=0
      bad "north-coord does not execute the recognized runtime selector: ${NORTH_COORD_EXEC_PATH:-missing}"
    fi

    if [[ "$north_coord_pid" =~ ^[1-9][0-9]*$ ]] &&
       [ -r "/proc/$north_coord_pid/environ" ] &&
       [ -r "/proc/$north_coord_pid/cmdline" ]; then
      north_coord_process_env="$(tr '\0' '\n' <"/proc/$north_coord_pid/environ")"
      north_coord_process_cmdline="$(tr '\0' '\n' <"/proc/$north_coord_pid/cmdline")"
      north_coord_mode="$(environment_lines_value "$north_coord_process_env" NORTH_FRAM_RUNTIME 2>/dev/null || true)"
      north_coord_source="$(environment_lines_value "$north_coord_process_env" FRAM_RUNTIME_SOURCE 2>/dev/null || true)"
      north_coord_revision="$(environment_lines_value "$north_coord_process_env" FRAM_RUNTIME_REV 2>/dev/null || true)"
      north_coord_tree="$(environment_lines_value "$north_coord_process_env" FRAM_RUNTIME_TREE 2>/dev/null || true)"
      north_coord_origin="$(environment_lines_value "$north_coord_process_env" FRAM_RUNTIME_ORIGIN 2>/dev/null || true)"
      north_coord_daemon="$(environment_lines_value "$north_coord_process_env" FRAM_RUNTIME_DAEMON 2>/dev/null || true)"
      north_coord_runtime_state=''
      if select_north_coord_runtime_state \
           "$north_coord_process_env" "$NORTH_COORD_UNIT" \
           "$NORTH_COORD_EXEC_KIND"; then
        north_coord_runtime_state="$NORTH_COORD_RUNTIME_STATE_ROOT"
        north_coord_selector="$north_coord_runtime_state/current"
        north_coord_active_generation="$north_coord_runtime_state/active"
      else
        north_coord_ok=0
        bad "north-coord runtime selector state is invalid: ${NORTH_COORD_RUNTIME_STATE_REASON:-missing identity}"
      fi
      if ! grep -Fxq "$CANONICAL_FRAM_LOG" <<<"$north_coord_process_cmdline"; then
        north_coord_ok=0
        bad "north-coord process does not serve canonical coordination.log"
      fi
      if [ -n "$north_coord_runtime_state" ] &&
         north_coord_runtime_identity_is_valid \
           "$north_coord_mode" "$north_coord_source" "$north_coord_revision" \
           "$north_coord_tree" "$north_coord_origin" "$north_coord_daemon" \
           "$north_coord_selector"; then
        ok_detail "north-coord runtime identity is exact: $north_coord_mode@$north_coord_revision ($north_coord_source)"
      elif [ -n "$north_coord_runtime_state" ]; then
        north_coord_ok=0
        bad "north-coord runtime identity is invalid: ${NORTH_COORD_RUNTIME_IDENTITY_REASON:-missing identity}"
      fi
      if [ -n "$north_coord_runtime_state" ] &&
         north_coord_runtime_record_owner_is_valid \
           "$north_coord_process_env" "$north_coord_pid" \
           "$north_coord_active_generation"; then
        ok_detail "north-coord owner token matches the active runtime record for systemd MainPID"
      elif [ -n "$north_coord_runtime_state" ] &&
           [ "$NORTH_COORD_RUNTIME_OWNER_REASON" = 'process generation is not the active runtime generation' ]; then
        # The MainPID is running a real, valid generation that is simply
        # older than the one now marked active (built ahead of it) — not a
        # broken owner record. A restart, not a failure, resolves this.
        north_coord_active_generation_name="$(basename "$(readlink -f "$north_coord_active_generation" 2>/dev/null)" 2>/dev/null)"
        soft "north-coord runtime built-ahead: restart to adopt gen-${north_coord_active_generation_name:-unknown}"
      elif [ -n "$north_coord_runtime_state" ]; then
        north_coord_ok=0
        bad "north-coord runtime ownership record is invalid: ${NORTH_COORD_RUNTIME_OWNER_REASON:-missing identity}"
      fi
      if [ ! -r "/proc/$north_coord_pid/cgroup" ] ||
         ! grep -Eq "^[^:]*:[^:]*:/system\.slice/${NORTH_COORD_UNIT//./\\.}(/|\$)" "/proc/$north_coord_pid/cgroup"; then
        north_coord_ok=0
        bad "north-coord MainPID is not owned by system.slice/$NORTH_COORD_UNIT"
      fi
      if command -v ss >/dev/null 2>&1; then
        mapfile -t north_coord_listener_pids < <(
          ss -H -ltnp 'sport = :7977' 2>/dev/null |
            north_coord_listener_pids_from_ss
        )
        if north_coord_listener_set_matches_mainpid \
             "$north_coord_pid" "${north_coord_listener_pids[@]}"; then
          ok_detail "north-coord systemd MainPID owns the :7977 listening socket"
        elif [ "${#north_coord_listener_pids[@]}" -gt 0 ] &&
             north_coord_listeners_are_proxy_fronted "${north_coord_listener_pids[@]}" &&
             north_coord_safety_ok; then
          ok_detail "north-coord :7977 listener(s) are fronted by system.slice/north-coord-proxy.service; coord-safety identity OK"
        else
          north_coord_ok=0
          north_coord_listener_detail=''
          for north_coord_listener_pid in "${north_coord_listener_pids[@]}"; do
            north_coord_listener_cgroup="$(tr '\n' ' ' <"/proc/$north_coord_listener_pid/cgroup" 2>/dev/null || printf unreadable)"
            north_coord_listener_detail+=" pid=$north_coord_listener_pid cgroup=$north_coord_listener_cgroup"
          done
          bad "north-coord :7977 listener PID does not equal systemd MainPID, is not fully proxy-cgroup-fronted, or coord-safety identity check failed (MainPID: $north_coord_pid; listeners:${north_coord_listener_detail:- missing})"
        fi
      else
        north_coord_ok=0
        bad "ss is required to verify north-coord MainPID socket ownership"
      fi
    else
      north_coord_ok=0
      bad "north-coord MainPID is missing or its process identity is unreadable: ${north_coord_pid:-missing}"
    fi

    if [ "$north_coord_ok" -eq 1 ]; then
      north_coord_runtime="$north_coord_mode ${north_coord_revision:0:12} · atomic selector · canonical coordination.log · fenced"
    elif [[ "$NORTH_COORD_EXEC_KIND" == direct-* ]]; then
      north_coord_runtime='direct runtime bypass (invalid)'
    else
      north_coord_runtime='deployment identity drift detected'
    fi
  else
    bad "no north-coord systemd unit is active (checked the route-map slot, then green/blue, then legacy north-coord.service)"
    north_coord_runtime='inactive'
  fi
  anthropic_installed='unknown'
  anthropic_authenticated='unknown'
  anthropic_headroom='unknown'
  anthropic_routing='unknown'
  openai_installed='unknown'
  openai_authenticated='unknown'
  openai_headroom='unknown'
  openai_routing='unknown'
  if command -v "${NORTH_PACKAGED_BIN:-north-packaged}" >/dev/null 2>&1; then
    if provider_output="$(run_north_packaged providers --json 2>&1)"; then
      if anthropic_fields="$(printf '%s\n' "$provider_output" | "$REPO/scripts/agent-provider-status.sh" anthropic)"; then
        IFS='|' read -r anthropic_installed anthropic_authenticated anthropic_headroom anthropic_routing <<<"$anthropic_fields"
        [ "$anthropic_installed" = yes ] || bad "North reports Anthropic not installed"
        [ "$anthropic_authenticated" = yes ] || bad "North reports Anthropic not authenticated"
      else bad "North omitted or malformed Anthropic capability status:\n$provider_output"; fi
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
    "Coordinator $north_coord_runtime" \
    'Surface     CLI/MCP only · web deployment retired' \
    "Anthropic   installed=$anthropic_installed · authenticated=$anthropic_authenticated · routing=$anthropic_routing · headroom=$anthropic_headroom" \
    "OpenAI      installed=$openai_installed · authenticated=$openai_authenticated · routing=$openai_routing · headroom=$openai_headroom" \
    "Allocation  ${allocation_summary:-unknown}"
else
  provider_group North "$before" \
    'Runtime     deployment identity/env/socket probes deferred to --local' \
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
