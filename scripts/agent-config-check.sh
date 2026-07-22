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
  run_bounded_process "$duration" "${CLAUDE_BIN:-claude}" "$@"
}

run_codex_probe() {
  local duration="$1"
  shift
  run_bounded_process "$duration" "${CODEX_BIN:-codex}" "$@"
}

gaffer_version_matches() {
  local version="$1" commit="$2"

  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ "$version" =~ ^[0-9a-f]{12}$|^[0-9a-f]{40}$ ]] || return 1
  [ "$version" = "$commit" ] || [ "$version" = "${commit:0:12}" ]
}

gaffer_revisions_converged() {
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
  local declared="$1" canonical_root="$2" resolved hash

  [ -x "$declared" ] || return 1
  resolved="$(readlink -f "$declared" 2>/dev/null)" || return 1
  case "$resolved" in
    "$canonical_root"/*) ;;
    *) return 1 ;;
  esac
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
  if [[ "$path" =~ ^/nix/store/[a-z0-9]{32}-fram[^/]*/bin/fram-daemon$ ]]; then
    NORTH_COORD_EXEC_KIND='direct-package'
    return 1
  fi
  case "$path" in
    */code/fram/bin/fram-daemon)
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

north_coord_runtime_identity_is_valid() {
  local mode="$1" source="$2" revision="$3" tree="$4" origin="$5" daemon="$6" selector="$7"
  local canonical_source canonical_selector canonical_daemon expected_source
  local observed_revision observed_tree observed_common observed_origin top_level worktree_status

  NORTH_COORD_RUNTIME_IDENTITY_REASON=''
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON='revision is not an exact Git SHA'
    return 1
  }
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
  [ "$canonical_source" = "$canonical_selector" ] || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON='runtime source and stable selector resolve differently'
    return 1
  }
  [ -x "$canonical_source/bin/fram-daemon" ] || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON='selected Fram daemon is not executable'
    return 1
  }
  canonical_daemon="$(realpath -e "$daemon" 2>/dev/null)" || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON="runtime daemon is missing: $daemon"
    return 1
  }
  [ "$canonical_daemon" = "$canonical_source/bin/fram-daemon" ] || {
    NORTH_COORD_RUNTIME_IDENTITY_REASON='runtime daemon is not the selected physical Fram daemon'
    return 1
  }

  case "$mode" in
    checkout)
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
      [[ "$canonical_source" =~ ^/nix/store/[a-z0-9]{32}-fram[^/]*$ ]] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package source is not a direct Fram Nix-store root'
        return 1
      }
      [ "$tree" = "immutable:$revision" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package tree marker does not bind its package revision'
        return 1
      }
      [ "$origin" = "$canonical_source" ] || {
        NORTH_COORD_RUNTIME_IDENTITY_REASON='package origin does not name its immutable store root'
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
                ],
            },
            {
                "matcher": "^Bash$",
                "hooks": [
                    command("agent-spawn-guard.sh", 10),
                    command("tripwire-guard.sh", 10),
                    command("firn-guard.sh", 10),
                    command("north-clock-guard-codex", 10),
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

if [ "${1:-}" = "$AGENT_CONFIG_BOUNDED_CHILD_MODE" ]; then
  shift
  probe_child_main "$@"
  exit 125
fi

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO/dotfiles/agents"
CLAUDE="$REPO/dotfiles/claude"
CODEX="$REPO/dotfiles/codex"
LIVE_REPO="${AGENT_CONFIG_LIVE_REPO:-$HOME/code/nixos-config}"
LIVE_SHARED="$LIVE_REPO/dotfiles/agents"
LIVE_CLAUDE="$LIVE_REPO/dotfiles/claude"
LIVE_CODEX="$LIVE_REPO/dotfiles/codex"
LIVE_HERMES="$LIVE_REPO/dotfiles/hermes"
CODEX_REQUIREMENTS="$REPO/modules/codex/requirements.toml"
CODEX_LEGACY_HOOKS="${CODEX_LEGACY_HOOKS:-$CODEX/hooks.json}"
HERMES="${AGENT_CONFIG_HERMES:-$REPO/dotfiles/hermes}"
HERMES_BRIDGE="$HERMES/plugins/north-bridge"
HERMES_MODULE="${AGENT_CONFIG_HERMES_MODULE:-$REPO/modules/hermes/default.bnix}"
GAFFER_SYNC="$REPO/scripts/claude-gaffer-plugin-sync.sh"
LAUNCHER_BIN="$REPO/dotfiles/bin"
LOCAL=0
VERBOSE=0
CANONICAL_FRAM_LOG="$HOME/.local/state/north/coordination.log"
CANONICAL_FRAM_TELEMETRY_LOG="$HOME/.local/state/north/telemetry.log"
CANONICAL_FRAM_THREADS="$HOME/.local/state/north/threads"
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

# Shared constitution, skills, and executable hook implementations.
before=$fail
hook_count=0
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r hook; do
    hook_count=$((hook_count + 1))
    if output="$(shellcheck -S warning "$hook" 2>&1)"; then
      ok_detail "shellcheck ${hook##*/}"
    else bad "shellcheck ${hook##*/}:\n$output"; fi
  done < <(find "$SHARED/hooks" -maxdepth 1 -type f -name '*.sh' -print | sort)
else bad "shellcheck is required to lint shared hooks"; fi
skill_count=0
while IFS= read -r skill; do
  skill_count=$((skill_count + 1))
  if [ "$(head -n 1 "$skill")" = '---' ]; then ok_detail "${skill%/SKILL.md} has frontmatter"
  else soft "${skill#"$REPO"/} lacks SKILL.md frontmatter"; fi
done < <(find "$SHARED/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f -print | sort)
if [ -s "$SHARED/AGENTS.md" ]; then ok_detail "canonical AGENTS.md present"
else bad "canonical AGENTS.md is missing or empty"; fi
group shared "$hook_count hooks linted · $skill_count skills · canonical instructions" "$before"

# Validate a provider hook manifest. In-repo commands must resolve to the shared
# hook implementation. External North lifecycle hooks are strict on a local
# machine and informational in repository-only/CI mode.
validate_hooks() {
  local manifest="$1" provider="$2" expected_provider="$3"
  local count=0 ev command raw_command provider_marker identity_kind first resolved expected basename declared_shared interpreter
  local hook_sha role provenance_manifest provenance_digest expected_resolved
  local -A provenance_seen=()
  HOOK_PROVENANCE_SUMMARY='development checkout (mutable) · provenance deferred to --local'
  while IFS=$'\t' read -r ev command; do
    [ -n "$command" ] || continue
    count=$((count + 1))
    raw_command="$command"
    provider_marker=''
    interpreter=''
    if [[ "$command" =~ ^AGENT_PROVIDER=([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
      provider_marker="${BASH_REMATCH[1]}"
      command="${BASH_REMATCH[2]}"
    fi
    if [[ "$command" =~ ^/run/current-system/sw/bin/bash[[:space:]]+(.+)$ ]]; then
      interpreter='/run/current-system/sw/bin/bash'
      command="${BASH_REMATCH[1]}"
    fi
    first="${command%% *}"
    basename="${first##*/}"
    identity_kind=''
    case "$first" in
      /home/tom/code/north/bin/north-on-spawn) identity_kind='spawn' ;;
      /home/tom/code/north/bin/north-on-tooluse) identity_kind='repair' ;;
    esac
    expected="$SHARED/hooks/$basename"
    declared_shared=0
    case "$first" in
      "/home/tom/code/nixos-config/dotfiles/agents/hooks/$basename"|"/home/tom/code/nixos-config/dotfiles/claude/hooks/$basename"|"$expected"|"$basename")
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
    elif [[ "$first" = /home/tom/code/north/bin/* ]]; then
      if [ "$LOCAL" -eq 1 ]; then
        if IFS=$'\t' read -r resolved hook_sha \
          < <(hook_target_fingerprint "$first" /home/tom/code/north); then
          role="$basename:north-lifecycle"
          if record_live_hook_binding "$role" "$resolved" "$hook_sha"; then
            provenance_seen["$resolved"$'\t'"$hook_sha"]=1
            ok_detail "$provider $ev → North $basename · development checkout (mutable): $resolved · sha256=$hook_sha"
          else
            bad "$provider $ev split North hook binding: $HOOK_SPLIT_REASON"
          fi
        else
          bad "$provider $ev North hook is missing/non-executable or resolves outside /home/tom/code/north: $first"
        fi
      else note "$provider $ev uses external North hook ${first##*/} (local check deferred)"; fi
    elif [ "$declared_shared" -eq 1 ] && [ -x "$expected" ]; then
      if [ "$LOCAL" -eq 1 ]; then
        expected_resolved="$(readlink -f "$LIVE_SHARED/hooks/$basename" 2>/dev/null || true)"
        if IFS=$'\t' read -r resolved hook_sha \
          < <(hook_target_fingerprint "$first" "$LIVE_REPO") &&
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
    else bad "$provider $ev hook is missing, non-executable, or outside canonical hooks: $raw_command"; fi
  done < <(jq -r '.hooks // {} | to_entries[] | .key as $event | .value[] | .hooks[]? | select(.type == "command") | [$event,.command] | @tsv' "$manifest")
  if [ "$LOCAL" -eq 1 ] && [ "${#provenance_seen[@]}" -gt 0 ]; then
    provenance_manifest="$(
      printf '%s\n' "${!provenance_seen[@]}" |
        sort
    )"
    provenance_digest="$(printf '%s\n' "$provenance_manifest" | sha256sum | awk '{print $1}')"
    HOOK_PROVENANCE_SUMMARY="development checkout (mutable) · ${#provenance_seen[@]} canonical targets · manifest sha256=$provenance_digest"
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
  if [ "$CODEX_MANAGED_BINDINGS" = 17 ]; then
    ok_detail 'Codex managed-only, fail-closed, remote-control-disabled policy is the exact 17-binding authoritative contract'
  else
    bad 'Codex managed requirements differ from the authoritative hook contract'
  fi

  local module="$REPO/modules/codex/default.bnix"
  local source relative live expected resolved north_revision
  local -a sources=(
    '/modules/codex/requirements.toml'
    '/dotfiles/agents/hooks/beagle-session-start.sh'
    '/dotfiles/agents/hooks/agent-spawn-guard.sh'
    '/dotfiles/agents/hooks/code-upstream-guard.sh'
    '/dotfiles/agents/hooks/firn-guard.sh'
    '/dotfiles/agents/hooks/north-clock-guard.sh'
    '/dotfiles/agents/hooks/north-clock-guard.py'
    '/dotfiles/agents/hooks/tripwire-guard.sh'
    '/dotfiles/agents/hooks/logcompress-hook.js'
    '/dotfiles/agents/hooks/logcompress.js'
    '/dotfiles/agents/hooks/racket-build-guard.sh'
    '/dotfiles/agents/hooks/lib/authoring-killswitch.sh'
    '/dotfiles/codex/hooks/north-on-spawn-codex'
    '/dotfiles/codex/hooks/north-on-tooluse-codex'
    '/dotfiles/codex/hooks/north-mark-delegated-codex'
    '/dotfiles/codex/hooks/north-on-stop-codex'
    '/dotfiles/codex/hooks/north-clock-guard-codex'
  )
  for source in "${sources[@]}"; do
    if grep -Fq "(s flakeRoot \"$source\")" "$module"; then :
    else bad "Codex module does not install managed-hook source $source"; fi
  done
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
     grep -Fq '{:source inputs.north}' "$module"; then
    ok_detail 'Codex module pins the complete North hook runtime from inputs.north'
  else
    bad 'Codex module does not install the exact inputs.north hook runtime'
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
  if python3 - "$SHARED/hooks/north-clock-guard.py" <<'PY'
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
    if cmp -s "$CODEX_REQUIREMENTS" /etc/codex/requirements.toml; then :
    else
      generation_exact=0
      bad 'Codex managed requirements are not the current /etc generation'
    fi
    for source in "${sources[@]:1}"; do
      relative="${source#/dotfiles/agents/hooks/}"
      if [ "$relative" = "$source" ]; then
        relative="${source#/dotfiles/codex/hooks/}"
      fi
      live="/etc/codex/hooks/$relative"
      expected="$REPO$source"
      resolved="$(readlink -f "$live" 2>/dev/null || true)"
      if [ -n "$resolved" ] && [[ "$resolved" = /nix/store/* ]] &&
         cmp -s "$expected" "$live"; then :
      else
        generation_exact=0
        bad "Codex managed hook $live is not the exact store-backed Firn source"
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
    north_revision="$(
      jq -er '.nodes.north.locked.rev | select(test("^[0-9a-f]{40}$"))' \
        "$REPO/flake.lock" 2>/dev/null || true
    )"
    for relative in \
      bin/north-on-spawn \
      bin/north-on-tooluse \
      bin/north-mark-delegated \
      bin/north-on-stop; do
      if [ -n "$north_revision" ] &&
         git -C "$HOME/code/north" cat-file -e "$north_revision:$relative" 2>/dev/null &&
         cmp -s "/etc/codex/hooks/north/$relative" \
           <(git -C "$HOME/code/north" show "$north_revision:$relative"); then :
      else
        generation_exact=0
        bad "Codex North runtime $relative does not match locked revision ${north_revision:-missing}"
      fi
    done
    if [ "$generation_exact" -eq 1 ]; then
      CODEX_HOOK_PROVENANCE='immutable /nix/store generation · exact Firn + locked North sources'
      ok_detail 'Codex authoritative hook generation is exact, immutable, and store-backed'
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
claude_gaffer='cache freshness deferred to --local'
need_json "$CLAUDE/settings.json" 'Claude settings'
if command -v shellcheck >/dev/null 2>&1 && shellcheck -S warning "$CLAUDE/statusline.sh"; then
  ok_detail "Claude statusline shellcheck"
else bad "Claude statusline shellcheck failed"; fi
if jq -e '.statusLine.type == "command" and .statusLine.command == "bash \"$HOME/code/nixos-config/dotfiles/claude/statusline.sh\""' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail "Claude statusline points at canonical adapter"
else bad "Claude statusline is not wired to $CLAUDE/statusline.sh"; fi
if bash "$CLAUDE/statusline.test.sh" >/dev/null; then
  ok_detail "Claude statusline observer is detached and output-safe"
else bad "Claude statusline observer test failed"; fi
if command -v shellcheck >/dev/null 2>&1 && \
   shellcheck -S warning "$LAUNCHER_BIN/claude" "$LAUNCHER_BIN/codex" "$LAUNCHER_BIN/launcher.test.sh"; then
  ok_detail "Account launcher wrappers shellcheck"
else bad "Account launcher wrappers shellcheck failed"; fi
if bash "$LAUNCHER_BIN/launcher.test.sh" >/dev/null; then
  ok_detail "Account launcher fallbacks are diagnostic (missing/nonzero/empty/malformed north, no-eligible, absent dir, clean pick)"
else bad "Account launcher diagnostics test failed"; fi
if jq -e '.autoMemoryEnabled == false' "$CLAUDE/settings.json" >/dev/null; then ok_detail "auto-memory disabled"
else bad "Claude autoMemoryEnabled must be false"; fi
if jq -e '
  .enabledPlugins["gaffer@gaffer"] == true
  and .extraKnownMarketplaces.gaffer.source == {
    "source": "directory",
    "path": "/home/tom/.local/state/north/gaffer-plugin-source"
  }
' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail "Gaffer plugin uses the managed exact-revision marketplace"
else
  bad "Claude Gaffer plugin must be enabled from /home/tom/.local/state/north/gaffer-plugin-source"
fi
if command -v shellcheck >/dev/null 2>&1 && shellcheck -S warning "$GAFFER_SYNC"; then
  ok_detail "Gaffer plugin sync shellcheck"
else bad "Gaffer plugin sync shellcheck failed"; fi
validate_hooks "$CLAUDE/settings.json" Claude anthropic
if jq -e '
  [
    .hooks.PreToolUse[]?.hooks[]?
    | select(
        .type == "command"
        and (.command | endswith("/north-clock-guard.sh"))
      )
    | .command
  ] as $commands
  | ($commands | length) == 2
    and all(
      $commands[];
      . == "/run/current-system/sw/bin/bash /home/tom/code/nixos-config/dotfiles/claude/hooks/north-clock-guard.sh"
    )
' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail 'Claude clock guard uses root-managed exact Bash for both bindings'
else
  bad 'Claude clock guard must use root-managed exact Bash for both bindings'
fi
require_manifest_guard_count "$CLAUDE/settings.json" Claude Bash 1 'user Bash topology guard is bound once'
claude_bindings="$HOOK_BINDINGS"
claude_hook_provenance="$HOOK_PROVENANCE_SUMMARY"
if [ "$LOCAL" -eq 1 ]; then
  canonical_link "$HOME/.claude/settings.json" "$LIVE_CLAUDE/settings.json" "$HOME/.claude/settings.json"
  canonical_link "$HOME/.claude/skills" "$LIVE_SHARED/skills" "$HOME/.claude/skills"
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
  if command -v claude >/dev/null 2>&1; then
    claude_mcp_status=0
    claude_mcp_output="$(
      run_claude_probe "${MCP_PROBE_TIMEOUT_SECONDS:-20}" mcp list 2>&1
    )" || claude_mcp_status=$?
    if [ "$claude_mcp_status" -eq 0 ]; then
      claude_mcp_exact=1
      for server in north fram linear-mcp-msa-new; do
        grep -Eq "^${server}:.*Connected" <<<"$claude_mcp_output" || {
          claude_mcp_exact=0
          bad "Claude MCP '$server' is missing or not connected:\n$claude_mcp_output"
        }
      done
      if [ "$claude_mcp_exact" -eq 1 ]; then
        claude_north="connected; $claude_north_topology"
        claude_fram="connected; $claude_fram_topology"
        claude_linear='connected'
        ok_detail "Claude reports North + Fram + Linear MCP connected"
      fi
    elif [ "$claude_mcp_status" -eq 124 ]; then
      bad "Claude MCP health probe timed out after ${MCP_PROBE_TIMEOUT_SECONDS:-20}s; its process group was reaped"
    else
      bad "claude rejected its config while checking MCP health (exit $claude_mcp_status):\n$claude_mcp_output"
    fi
    gaffer_source="$HOME/.local/state/north/gaffer-plugin-source"
    gaffer_expected="$(jq -er '.nodes.gaffer.locked.rev | select(test("^[0-9a-f]{40}$"))' "$REPO/flake.lock" 2>/dev/null || true)"
    gaffer_plugin_probe_status=0
    gaffer_plugins="$(
      run_claude_probe "${PLUGIN_PROBE_TIMEOUT_SECONDS:-15}" plugin list --json 2>/dev/null
    )" || gaffer_plugin_probe_status=$?
    if [ "$gaffer_plugin_probe_status" -eq 0 ] &&
       gaffer_version="$(jq -er '
         [.[] | select(.id == "gaffer@gaffer")]
         | if length == 1 then .[0].version else error("expected one Gaffer plugin") end
       ' <<<"$gaffer_plugins")" &&
       [ -n "$gaffer_expected" ] &&
       gaffer_source_head="$(git -C "$gaffer_source" rev-parse --verify HEAD 2>/dev/null)" &&
       gaffer_source_top="$(git -C "$gaffer_source" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)" &&
       gaffer_source_common="$(git -C "$gaffer_source" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" &&
       gaffer_home_common="$(git -C "$HOME/code/gaffer" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" &&
       gaffer_source_git_dir="$(git -C "$gaffer_source" rev-parse --path-format=absolute --git-dir 2>/dev/null)" &&
       gaffer_version_resolved="$(git -C "$gaffer_source" rev-parse --verify "$gaffer_version^{commit}" 2>/dev/null)"; then
      gaffer_source_dirty="$(git -C "$gaffer_source" status --porcelain --untracked-files=all 2>/dev/null || printf status-unavailable)"
      gaffer_source_ref="$(git -C "$gaffer_source" symbolic-ref --quiet HEAD 2>/dev/null || true)"
      gaffer_marker=''
      if [ -f "$gaffer_source_git_dir/north-managed-gaffer-plugin-source" ]; then
        IFS= read -r gaffer_marker \
          <"$gaffer_source_git_dir/north-managed-gaffer-plugin-source" || true
      fi
      gaffer_exact=1
      managed_source_root_matches "$gaffer_source" "$gaffer_source_top" || {
        gaffer_exact=0
        bad "managed Gaffer source root mismatch: observed $gaffer_source_top, expected canonical identity of $gaffer_source"
      }
      [ "$gaffer_source_common" = "$gaffer_home_common" ] || {
        gaffer_exact=0
        bad "managed Gaffer source is not a worktree of $HOME/code/gaffer"
      }
      [ "$gaffer_marker" = north-gaffer-plugin-source-v1 ] || {
        gaffer_exact=0
        bad "managed Gaffer source lacks the sync ownership marker"
      }
      if gaffer_intent_revision="$(jq -er \
        --arg source "$gaffer_source" \
        --arg commonDir "$gaffer_home_common" '
          if type == "object"
             and (keys | sort) == ["commonDir", "revision", "source", "version"]
             and .version == "north-gaffer-plugin-source-intent-v1"
             and .source == $source
             and .commonDir == $commonDir
             and (.revision | type) == "string"
             and (.revision | test("^[0-9a-f]{40}$"))
          then .revision
          else error("invalid ownership intent")
          end
        ' "$gaffer_source.intent" 2>/dev/null)" &&
         git -C "$gaffer_source" cat-file -e "$gaffer_intent_revision^{commit}" 2>/dev/null; then
        if ! gaffer_revisions_converged \
          "$gaffer_intent_revision" "$gaffer_source_head" "$gaffer_expected"; then
          gaffer_exact=0
          bad "managed Gaffer intent is ${gaffer_intent_revision:0:12}; source/input are ${gaffer_source_head:0:12}/${gaffer_expected:0:12}"
        fi
      else
        gaffer_exact=0
        bad "managed Gaffer source lacks a valid durable creation intent"
      fi
      [ -z "$gaffer_source_ref" ] || {
        gaffer_exact=0
        bad "managed Gaffer source is attached to $gaffer_source_ref, expected detached exact revision"
      }
      [ -z "$gaffer_source_dirty" ] || {
        gaffer_exact=0
        bad "managed Gaffer source has unexpected tracked or untracked changes"
      }
      [ "$gaffer_source_head" = "$gaffer_expected" ] || {
        gaffer_exact=0
        bad "managed Gaffer source is ${gaffer_source_head:0:12}, verified input is ${gaffer_expected:0:12}"
      }
      if ! gaffer_version_matches "$gaffer_version" "$gaffer_expected" ||
         [ "$gaffer_version_resolved" != "$gaffer_expected" ]; then
        gaffer_exact=0
        bad "Claude Gaffer cache is $gaffer_version, verified input is ${gaffer_expected:0:12}"
      fi
      if [ "$gaffer_exact" -eq 1 ]; then
        claude_gaffer="exact verified input ${gaffer_expected:0:12}"
        ok_detail "Claude Gaffer cache + managed source match exact verified input $gaffer_expected"
      else
        claude_gaffer="exact-input drift detected"
      fi
      else
      if [ "$gaffer_plugin_probe_status" -eq 124 ]; then
        bad "Claude Gaffer plugin-list probe timed out after ${PLUGIN_PROBE_TIMEOUT_SECONDS:-15}s; its process group was reaped"
      elif [ "$gaffer_plugin_probe_status" -eq 0 ]; then
        bad "Claude Gaffer cache/managed-source exact revision could not be determined after the bounded plugin list succeeded"
      else
        bad "Claude Gaffer plugin/managed-source exact revision could not be determined (plugin-list exit $gaffer_plugin_probe_status)"
      fi
      claude_gaffer='freshness unknown'
    fi
  else bad "claude CLI is missing from PATH"; fi
fi
provider_group Claude "$before" \
  "Hooks       $claude_bindings bindings" \
  'Identity    adapter-pinned native spawn + repair → anthropic' \
  'Topology    user Bash hook (loaded directly by Claude)' \
  "Hook source $claude_hook_provenance" \
  "Bootstrap   static config parsed · Gaffer $claude_gaffer" \
  "MCP         North: $claude_north" \
  "            Fram: $claude_fram" \
  "            Linear: $claude_linear"

before=$fail
note_ignored_codex_legacy_manifest "$CODEX_LEGACY_HOOKS"
need_toml "$CODEX/config.toml" 'Codex config'
validate_codex_managed_policy
codex_bindings="${CODEX_MANAGED_BINDINGS:-invalid}"
codex_hook_provenance="${CODEX_HOOK_PROVENANCE:-declaration drift detected}"
ok_detail 'Codex legacy ~/.codex/hooks.json is intentionally ignored; it contributes zero active bindings'
codex_north='declared; canonical explicit instance env; live probe deferred'
codex_fram='declared; canonical split corpus; live probe deferred'
codex_linear='auth probe deferred to --local'
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
  canonical_link "$HOME/.codex/config.toml" "$LIVE_CODEX/config.toml" "$HOME/.codex/config.toml"
  canonical_link "$HOME/.codex/AGENTS.md" "$LIVE_SHARED/AGENTS.md" "$HOME/.codex/AGENTS.md"
  canonical_link "$HOME/.agents/skills" "$LIVE_SHARED/skills" "$HOME/.agents/skills"
  if command -v codex >/dev/null 2>&1; then
    codex_mcp_status=0
    mcp_output="$(
      run_codex_probe "${MCP_PROBE_TIMEOUT_SECONDS:-20}" mcp list 2>&1
    )" || codex_mcp_status=$?
    if [ "$codex_mcp_status" -eq 0 ]; then
      for server in north fram linear-mcp-msa-new; do
        grep -Eq "^${server}[[:space:]]" <<<"$mcp_output" ||
          bad "Codex MCP '$server' is missing/disabled"
      done
      linear_line="$(grep -E '^linear-mcp-msa-new[[:space:]]' <<<"$mcp_output" || true)"
      if [[ "$linear_line" = *'Not logged in'* ]]; then codex_linear='not logged in'
      elif [[ "$linear_line" = *OAuth* || "$linear_line" = *'Logged in'* ]]; then codex_linear='authenticated'
      else codex_linear='auth unknown'; fi
      ok_detail "Codex config parsed; North + Fram + Linear MCP listed"
      if [ "$codex_north_env_ok" -eq 1 ]; then
        codex_north='enabled; canonical explicit instance env'
      else
        codex_north='enabled; explicit instance env drift detected'
      fi
      codex_fram='enabled; canonical split corpus'
    elif [ "$codex_mcp_status" -eq 124 ]; then
      bad "Codex MCP-list probe timed out after ${MCP_PROBE_TIMEOUT_SECONDS:-20}s; its process group was reaped"
    else
      bad "codex rejected its config while listing MCPs (exit $codex_mcp_status):\n$mcp_output"
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
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet north-coord; then
    north_coord_env="$(systemctl show north-coord -p Environment --value 2>/dev/null || true)"
    north_coord_exec="$(systemctl show north-coord -p ExecStart --value 2>/dev/null || true)"
    north_coord_pid="$(systemctl show north-coord -p MainPID --value 2>/dev/null || true)"
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
      north_coord_selector="$HOME/.local/state/north/fram-runtime/current"
      if ! grep -Fxq "$CANONICAL_FRAM_LOG" <<<"$north_coord_process_cmdline"; then
        north_coord_ok=0
        bad "north-coord process does not serve canonical coordination.log"
      fi
      if north_coord_runtime_identity_is_valid \
           "$north_coord_mode" "$north_coord_source" "$north_coord_revision" \
           "$north_coord_tree" "$north_coord_origin" "$north_coord_daemon" \
           "$north_coord_selector"; then
        ok_detail "north-coord runtime identity is exact: $north_coord_mode@$north_coord_revision ($north_coord_source)"
      else
        north_coord_ok=0
        bad "north-coord runtime identity is invalid: ${NORTH_COORD_RUNTIME_IDENTITY_REASON:-missing identity}"
      fi
      if grep -q '^FRAM_RUNTIME_OWNER_TOKEN=' <<<"$north_coord_process_env"; then
        north_coord_ok=0
        bad "north-coord systemd service carries a direct-launch owner token"
      fi
      if [ ! -r "/proc/$north_coord_pid/cgroup" ] ||
         ! grep -Eq '^[^:]*:[^:]*:/system\.slice/north-coord\.service(/|$)' "/proc/$north_coord_pid/cgroup"; then
        north_coord_ok=0
        bad "north-coord MainPID is not owned by system.slice/north-coord.service"
      fi
      if command -v ss >/dev/null 2>&1; then
        mapfile -t north_coord_listener_pids < <(
          ss -H -ltnp 'sport = :7977' 2>/dev/null |
            north_coord_listener_pids_from_ss
        )
        if north_coord_listener_set_matches_mainpid \
             "$north_coord_pid" "${north_coord_listener_pids[@]}"; then
          ok_detail "north-coord systemd MainPID owns the :7977 listening socket"
        else
          north_coord_ok=0
          north_coord_listener_detail=''
          for north_coord_listener_pid in "${north_coord_listener_pids[@]}"; do
            north_coord_listener_cgroup="$(tr '\n' ' ' <"/proc/$north_coord_listener_pid/cgroup" 2>/dev/null || printf unreadable)"
            north_coord_listener_detail+=" pid=$north_coord_listener_pid cgroup=$north_coord_listener_cgroup"
          done
          bad "north-coord :7977 listener PID does not equal systemd MainPID (MainPID: $north_coord_pid; listeners:${north_coord_listener_detail:- missing})"
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
    bad "north-coord systemd service is not active"
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

if [ "$fail" -ne 0 ]; then printf 'agent-config-check: FAILED\n' >&2; exit 1; fi
if [ "$warn" -gt 0 ]; then printf 'agent-config-check: passed with %s warning(s)\n' "$warn"
else printf 'agent-config-check: all green\n'; fi
