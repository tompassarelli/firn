#!/usr/bin/env bash
# PreToolUse agent-spawn-guard — enforcement half of the north config dispatch setting.
# ============================================================================
# Successor of agent-redirect.sh (removed in the P6 hook cleanup, ae3b31e).
# Reinstated 2026-07-03: without a mechanical intercept, native catch-all
# spawns (general-purpose, serial, no claim trail) recurred — prose in
# CLAUDE.md demonstrably does not hold. Fires on subagent tool calls too,
# so nested native spawns are covered.
#
#   dispatch=north  -> DENY native Agent/Task/Workflow; hand back the north recipe
#   dispatch=warn   -> allow, inject a nudge (additionalContext)
#   dispatch=native -> allow silently
#
# A separate topology invariant applies to Bash regardless of dispatch mode:
#   AGENT_TOPOLOGY=worker -> DENY direct North/provider agent work + peer control
#   orchestrator/unset    -> allow (native sessions have no managed topology)
# This is a static command-position policy guard, not a shell security boundary:
# runtime-built commands (variables, functions, eval-generated text) are outside
# what a PreToolUse string inspection can resolve. Provider tool exposure remains
# the independent capability boundary.
#
# State:       ~/.local/state/north/harness.conf
#              (legacy ~/.claude/my-config.state is read only if absent)
#              flip via `north config dispatch <mode>`
# Kill-switch: persistent `north config guards off` (state) OR env
#              CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces
#              guards live). Shared impl: lib/authoring-killswitch.sh.
# ============================================================================
set -uo pipefail

# Kill-switch: shared semantics in lib/authoring-killswitch.sh — persistent
# `north config guards off` (state, live) or env CLAUDE_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

STATE_PATH="$HOME/.local/state/north/harness.conf"
type north_harness_state_path >/dev/null 2>&1 && STATE_PATH="$(north_harness_state_path)"
MODE=$(grep -E '^dispatch=' "$STATE_PATH" 2>/dev/null | tail -1 | cut -d= -f2-)
MODE="${MODE:-north}"
export AGENT_SPAWN_GUARD_MODE="$MODE"

read -r -d '' PY <<'PYEOF' || true
import sys, json, os, re, shlex

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = data.get("tool_name", "")
mode = os.environ.get("AGENT_SPAWN_GUARD_MODE", "north")
ti = data.get("tool_input", {}) or {}

CONTROL = {";", "&&", "||", "|", "|&", "&", "\n", "(", ")"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$", re.S)
REDIRECTION = re.compile(r"^\d*(?:<>|>>|<<|>|<).*$", re.S)
SHELLS = {"bash", "sh", "dash", "zsh", "fish", "ksh"}
SIMPLE_WRAPPERS = {"command", "exec", "nohup"}
HELP_VERSION_FLAGS = {"-h", "--help", "-V", "--version"}

def basename(token):
    return token.rstrip("/").rsplit("/", 1)[-1]

def command_substitutions(command):
    """Yield static $(...) / backtick bodies, excluding single-quoted prose."""
    bodies = []
    index, single, double = 0, False, False
    while index < len(command):
        char = command[index]
        if char == "\\" and not single:
            index += 2
            continue
        if char == "'" and not double:
            single = not single
            index += 1
            continue
        if char == '"' and not single:
            double = not double
            index += 1
            continue
        if not single and command.startswith("$(", index):
            start, cursor, depth = index + 2, index + 2, 1
            inner_single, inner_double = False, False
            while cursor < len(command):
                inner = command[cursor]
                if inner == "\\" and not inner_single:
                    cursor += 2
                    continue
                if inner == "'" and not inner_double:
                    inner_single = not inner_single
                elif inner == '"' and not inner_single:
                    inner_double = not inner_double
                elif not inner_single and not inner_double:
                    if inner == "(":
                        depth += 1
                    elif inner == ")":
                        depth -= 1
                        if depth == 0:
                            bodies.append(command[start:cursor])
                            break
                cursor += 1
            index = cursor + 1
            continue
        if not single and char == "`":
            cursor = index + 1
            while cursor < len(command):
                if command[cursor] == "\\":
                    cursor += 2
                    continue
                if command[cursor] == "`":
                    bodies.append(command[index + 1:cursor])
                    break
                cursor += 1
            index = cursor + 1
            continue
        index += 1
    return bodies

def command_segments(command):
    """Tokenize shell control flow while preserving quoted argument boundaries."""
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
        lexer.whitespace_split = True
        lexer.commenters = ""
        lexer.whitespace = " \t\r"
        tokens = list(lexer)
    except (ValueError, TypeError):
        return []

    segments, current = [], []
    for index, token in enumerate(tokens):
        # shlex splits fd redirects such as 2>&1 and &>file at '&'. They are
        # redirections, not new command positions.
        redirect_amp = token == "&" and (
            (current and current[-1].endswith(">"))
            or (index + 1 < len(tokens) and tokens[index + 1].startswith(">"))
        )
        if token in CONTROL and not redirect_amp:
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments

def skip_redirections(tokens, index):
    while index < len(tokens):
        token = tokens[index]
        if token in (">", ">>", "<", "<<", "<<<", "<>"):
            index += 2
        elif REDIRECTION.fullmatch(token):
            # 2>/dev/null is self-contained; bare 2> consumes the next token.
            index += 2 if token.endswith((">", "<")) else 1
        else:
            break
    return index

def initial_command(segment):
    index = 0
    while index < len(segment) and segment[index] in ("then", "do", "else", "elif", "if", "while", "until", "!", "{"):
        index += 1
    # A for/case/select/function header is syntax, not an executable. Its body
    # starts after a control separator and is inspected as another segment.
    if index < len(segment) and segment[index] in ("for", "case", "select", "function"):
        return None, []
    while index < len(segment) and ASSIGNMENT.fullmatch(segment[index]):
        index += 1
    index = skip_redirections(segment, index)
    if index >= len(segment):
        return None, []
    return segment[index], segment[index + 1:]

def drop_options(args, value_options=()):
    index = 0
    values = set(value_options)
    short_values = {
        option[1:] for option in values
        if re.fullmatch(r"-[A-Za-z0-9]", option)
    }
    while index < len(args):
        token = args[index]
        if token == "--":
            return args[index + 1:]
        name = token.split("=", 1)[0]
        if not token.startswith("-") or token == "-":
            break
        if name in values:
            index += 2 if "=" not in token else 1
            continue
        if token.startswith("--"):
            index += 1
            continue
        consumed_value = False
        for offset, flag in enumerate(token[1:]):
            if flag in short_values:
                index += 1 if token[1:][offset + 1:] else 2
                consumed_value = True
                break
        if not consumed_value:
            index += 1
    return args[index:]

def shell_command_strings(name, args):
    """Return every statically supplied shell command string."""
    command_strings = []
    index = 0
    value_flags = {"o", "O"}
    long_value_options = {"--init-file", "--rcfile"}

    while index < len(args):
        token = args[index]
        if token == "--":
            break
        if token.startswith("--"):
            option, separator, value = token.partition("=")
            if name == "fish" and option in ("--command", "--init-command"):
                if separator:
                    command_strings.append(value)
                    index += 1
                elif index + 1 < len(args):
                    command_strings.append(args[index + 1])
                    index += 2
                else:
                    index += 1
                if option == "--command":
                    break
                continue
            if option in long_value_options and not separator:
                index += 2
            else:
                index += 1
            continue
        if not token.startswith("-") or token == "-":
            break

        flags = token[1:]
        consumed_value = False
        for offset, flag in enumerate(flags):
            if flag == "c":
                attached = flags[offset + 1:] if name == "fish" else ""
                if attached:
                    command_strings.append(attached)
                    index += 1
                elif index + 1 < len(args):
                    command_strings.append(args[index + 1])
                    index += 2
                else:
                    index += 1
                consumed_value = True
                break
            if name == "fish" and flag == "C":
                attached = flags[offset + 1:]
                if attached:
                    command_strings.append(attached)
                    index += 1
                elif index + 1 < len(args):
                    command_strings.append(args[index + 1])
                    index += 2
                else:
                    index += 1
                consumed_value = True
                break
            if flag in value_flags:
                # -o/-O take an option name. An attached value ends this
                # cluster, so its letters must not be mistaken for more flags
                # (for example -Ocheckwinsize).
                index += 1 if flags[offset + 1:] else 2
                consumed_value = True
                break
        if not consumed_value:
            index += 1
        elif command_strings and flag == "c":
            break
    return command_strings

def expand_env_split_strings(args):
    """Expand statically supplied GNU env -S strings into executable argv."""
    expanded = list(args)
    for _ in range(12):
        replacement = None
        index = 0
        while index < len(expanded):
            token = expanded[index]
            if token == "--" or not token.startswith("-") or token == "-":
                break
            value = None
            consumed = 1
            prefix = ""
            if token in ("-S", "--split-string"):
                if index + 1 >= len(expanded):
                    return []
                value = expanded[index + 1]
                consumed = 2
            elif token.startswith("--split-string="):
                value = token.split("=", 1)[1]
            else:
                short = re.fullmatch(r"-([i0v]*)S(.*)", token, re.S)
                if short:
                    prefix, value = short.groups()
                    if not value:
                        if index + 1 >= len(expanded):
                            return []
                        value = expanded[index + 1]
                        consumed = 2
            if value is not None:
                try:
                    words = shlex.split(value, posix=True)
                except (ValueError, TypeError):
                    return []
                replacement = (
                    expanded[:index]
                    + (["-" + prefix] if prefix else [])
                    + words
                    + expanded[index + consumed:]
                )
                break
            if token in ("-a", "--argv0", "-u", "--unset", "-C", "--chdir"):
                index += 2
            elif token.startswith((
                "-a", "-u", "-C", "--argv0=", "--unset=", "--chdir=",
            )):
                index += 1
            else:
                index += 1
        if replacement is None:
            return expanded
        expanded = replacement
    return expanded

def unwrap(command, args):
    """Peel common command wrappers without scanning ordinary arguments."""
    for _ in range(12):
        name = basename(command)
        if name in SIMPLE_WRAPPERS:
            args = drop_options(args, ("-a", "--argv0") if name == "exec" else ())
        elif name == "env":
            args = expand_env_split_strings(args)
            args = drop_options(args, (
                "-a", "--argv0", "-u", "--unset", "-C", "--chdir",
            ))
            while args and ASSIGNMENT.fullmatch(args[0]):
                args = args[1:]
        elif name == "sudo":
            args = drop_options(args, (
                "-C", "--close-from", "-D", "--chdir", "-g", "--group",
                "-h", "--host", "-p", "--prompt", "-R", "--chroot",
                "-r", "--role", "-t", "--type", "-u", "--user",
                "-T", "--command-timeout",
            ))
        elif name == "time":
            args = drop_options(args, ("-f", "--format", "-o", "--output"))
        elif name == "nice":
            args = drop_options(args, ("-n", "--adjustment"))
        elif name == "timeout":
            args = drop_options(args, ("-k", "--kill-after", "-s", "--signal"))
            args = args[1:] if args else []  # duration
        elif name == "stdbuf":
            args = drop_options(args, ("-i", "--input", "-o", "--output", "-e", "--error"))
        elif name == "direnv" and args[:1] == ["exec"]:
            args = args[2:]  # `direnv exec DIR COMMAND ...`
        else:
            return command, args
        while args and ASSIGNMENT.fullmatch(args[0]):
            args = args[1:]
        if not args:
            return None, []
        command, args = args[0], args[1:]
    return command, args

def safe_dry_run(args):
    return "--dry-run" in args

def diagnostic_probe(args):
    return any(token in HELP_VERSION_FLAGS for token in args)

def has_option(args, *names):
    return any(token in names or any(token.startswith(name + "=") for name in names if name.startswith("--"))
               for token in args)

def first_positional(args, value_options=()):
    """Return (index, token) after known options without guessing option values."""
    values = set(value_options)
    index = 0
    while index < len(args):
        token = args[index]
        if token == "--":
            index += 1
            return (index, args[index]) if index < len(args) else (None, None)
        name = token.split("=", 1)[0]
        if not token.startswith("-") or token == "-":
            return index, token
        index += 2 if name in values and "=" not in token else 1
    return None, None

def positional_args(args, value_options=()):
    values, positionals, index = set(value_options), [], 0
    while index < len(args):
        token = args[index]
        if token == "--":
            positionals.extend(args[index + 1:])
            break
        name = token.split("=", 1)[0]
        if token.startswith("-") and token != "-":
            index += 2 if name in values and "=" not in token else 1
            continue
        positionals.append(token)
        index += 1
    return positionals

def provider_agent_turn(name, args):
    if name == "codex":
        codex_value_options = (
            "-c", "--config", "--enable", "--disable", "--remote",
            "--remote-auth-token-env", "-i", "--image", "-m", "--model",
            "--local-provider", "-p", "--profile", "-s", "--sandbox",
            "-C", "--cd", "--add-dir", "-a", "--ask-for-approval",
        )
        _, verb = first_positional(args, codex_value_options)
        if diagnostic_probe(args):
            return None
        if verb in (
            "app-server", "exec", "e", "exec-server", "fork", "mcp-server",
            "remote-control", "resume", "review", "sandbox",
        ):
            if verb in ("exec", "e") and "help" in args:
                return None
            return "codex " + verb
        # Cloud browsing/status is observation; `cloud exec` submits a remote
        # agent task and is therefore another provider-native work surface.
        positionals = positional_args(args, codex_value_options)
        if positionals[:2] == ["cloud", "exec"]:
            return "codex cloud exec"
        if positionals[:2] == ["debug", "app-server"]:
            return "codex debug app-server"
        commands = {
            "apply", "archive", "cloud", "completion", "debug", "delete",
            "doctor", "features", "help", "login", "logout", "mcp", "plugin",
            "unarchive", "update",
        }
        # With no command/prompt Codex opens an interactive agent session.
        # Managed workers may use the administrative/diagnostic commands above,
        # but may never open a second provider agent, prompted or otherwise.
        if verb is None:
            return "codex interactive session"
        if verb is not None and verb not in commands:
            return "codex prompt"
        return None

    if name != "claude":
        return None
    claude_value_options = (
        "--add-dir", "--agent", "--agents", "--allowedTools", "--allowed-tools",
        "--append-system-prompt", "--betas", "-d", "--debug", "--debug-file",
        "--disallowedTools", "--disallowed-tools", "--effort", "--fallback-model",
        "--file", "--from-pr", "--input-format", "--json-schema", "--max-budget-usd",
        "--mcp-config", "--model", "-n", "--name", "--output-format",
        "--permission-mode", "--plugin-dir", "--plugin-url", "--prompt-suggestions",
        "--remote-control", "--session-id", "--setting-sources", "--settings",
        "--system-prompt", "--tools", "-w", "--worktree",
    )
    positionals = positional_args(args, claude_value_options)
    verb = positionals[0] if positionals else None
    if diagnostic_probe(args) or verb in ("auth", "status", "doctor", "help"):
        return None
    if has_option(args, "-p", "--print"):
        return "claude --print"
    if has_option(args, "-c", "--continue"):
        if verb is not None:
            return "claude --continue prompt"
        return "claude --continue session"
    if has_option(args, "-r", "--resume"):
        # --resume may consume a session id; two positional values make a
        # resumed prompt explicit, but either form opens another agent session.
        inline_session = any(token.startswith(("-r=", "--resume=")) for token in args)
        if len(positionals) >= (1 if inline_session else 2):
            return "claude --resume prompt"
        return "claude --resume session"
    if verb == "ultrareview":
        return "claude ultrareview"
    if positionals[:2] == ["auto-mode", "critique"]:
        return "claude auto-mode critique"
    if positionals[:2] == ["mcp", "serve"]:
        return "claude mcp serve"
    if len(positionals) >= 2 and positionals[0] in ("plugin", "plugins") and positionals[1] == "eval":
        return "claude plugin eval"
    if verb == "agents":
        # JSON is an observation-only roster query. The interactive agent view
        # can dispatch background agents and is not a worker-owned surface.
        return None if "--json" in args else "claude agents"
    commands = {
        "auth", "auto-mode", "doctor", "gateway", "help", "install", "mcp",
        "plugin", "plugins", "project", "setup-token", "status", "update",
        "upgrade",
    }
    # With no prompt Claude opens an interactive agent session. Managed workers
    # may use the administrative/diagnostic commands above, but may never open
    # a second provider agent, prompted or otherwise.
    if verb is None:
        return "claude interactive session"
    if verb is not None and verb not in commands:
        return "claude prompt"
    return None

def north_config_mutation(args):
    """Identify state-changing `north config` calls while preserving reports."""
    if args[:1] != ["config"]:
        return None
    rest = args[1:]
    if not rest or rest[0] in ("status", "help", "-h", "--help"):
        return None
    read_only = {
        ("guards",), ("dispatch",), ("coord",), ("caveman",),
        ("beagle",), ("beagle", "list"),
        ("routing",), ("routing", "show"),
    }
    return None if tuple(rest) in read_only else "north config mutation"

def is_direct_spawn(command, args, cwd):
    command, args = unwrap(command, args)
    if not command:
        return None
    name = basename(command)

    # Recurse only into explicit shell -c scripts. Quoted prose passed to echo,
    # rg, test runners, Python, etc. remains an ordinary argument and is ignored.
    if name in SHELLS:
        for command_string in shell_command_strings(name, args):
            match = forbidden_shell(command_string, cwd)
            if match:
                return match
        shell_args = drop_options(args)
        if shell_args and basename(shell_args[0]) == "north":
            return is_direct_spawn(shell_args[0], shell_args[1:], cwd)
        return None

    if name in ("mcp__north__spawn", "mcp__north__dispatch"):
        return name

    provider_turn = provider_agent_turn(name, args)
    if provider_turn:
        return provider_turn

    if name == "north":
        config_mutation = north_config_mutation(args)
        if config_mutation:
            return config_mutation

    if name == "north" and args[:1] and args[0] in ("spawn", "delegate", "steer", "retask"):
        # Bare verbs print usage; a composed --dry-run does not launch a lane.
        dry_run_safe = args[0] in ("spawn", "delegate", "steer") and safe_dry_run(args[1:])
        if len(args) > 1 and not dry_run_safe:
            return "north " + args[0]
        return None

    if name in ("bb", "bun"):
        runtime_args = drop_options(args, ("-cp", "--classpath", "--cwd"))
        if name == "bun" and runtime_args[:1] == ["run"]:
            runtime_args = runtime_args[1:]
        if not runtime_args:
            return None
        entrypoint, entry_args = runtime_args[0], runtime_args[1:]
        normalized = entrypoint.replace("\\", "/")
        if (normalized.endswith("/north/cli/agents-cli.clj")
                or normalized.endswith("/cli/agents-cli.clj")
                or normalized == "cli/agents-cli.clj"):
            if entry_args[:1] and entry_args[0] in ("spawn", "delegate", "steer", "retask"):
                dry_run_safe = entry_args[0] in ("spawn", "delegate", "steer") and safe_dry_run(entry_args[1:])
                if len(entry_args) > 1 and not dry_run_safe:
                    return "agents-cli.clj " + entry_args[0]
            return None
        if (normalized.endswith("/north/cli/config-cli.clj")
                or normalized.endswith("/cli/config-cli.clj")
                or normalized == "cli/config-cli.clj"):
            return north_config_mutation(["config"] + entry_args)
        if (normalized.endswith("/north/cli/msg-cli.clj")
                or normalized.endswith("/cli/msg-cli.clj")
                or normalized == "cli/msg-cli.clj"):
            if len(entry_args) > 2 and entry_args[1] == "send-cmd":
                return "msg-cli.clj send-cmd"
            return None
        direct = re.search(r"(?:^|/)(?:north/)?sdk/src/(spawn|dispatch)\.ts$", normalized)
        if not direct and normalized in ("src/spawn.ts", "src/dispatch.ts"):
            direct = re.match(r"src/(spawn|dispatch)\.ts$", normalized) if re.search(r"/north/sdk/?$", cwd) else None
        if direct and entry_args:
            return "sdk/src/" + direct.group(1) + ".ts"
    return None

def forbidden_shell(command, cwd):
    if not isinstance(command, str):
        return None
    for nested in command_substitutions(command):
        match = forbidden_shell(nested, cwd)
        if match:
            return match
    for segment in command_segments(command):
        executable, args = initial_command(segment)
        if executable:
            match = is_direct_spawn(executable, args, cwd)
            if match:
                return match
    return None

if tool in ("Bash", "shell", "exec_command"):
    if os.environ.get("AGENT_TOPOLOGY", "").strip().lower() != "worker":
        sys.exit(0)
    command = ti.get("command", "")
    match = forbidden_shell(command, data.get("cwd", "") or "")
    if not match:
        sys.exit(0)
    reason = (
        "DENIED by Gaffer worker topology: worker lanes cannot spawn, delegate, "
        "dispatch, or command agents (matched " + match + "). Return the "
        "subtask, steering request, or escalation to the orchestrator; only an "
        "orchestrator owns fan-out and peer control. Emergency bypass is an "
        "operator/orchestrator action outside this worker; return an escalation "
        "instead of weakening your own guard."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)

if tool not in ("Agent", "Task", "Workflow") or mode == "native":
    sys.exit(0)

GAFFER_AGENTS = os.path.expanduser("~/code/gaffer/agents")
SAFE_ROLE = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
ROUTING_COMMENT = re.compile(r"<!--\s*GAFFER_ROUTING\s+(\{.*?\})\s*-->")

def routing_for(invoked_role):
    """Read the generated adapter contract; never infer provider dials here."""
    if not SAFE_ROLE.fullmatch(invoked_role):
        return None
    path = os.path.join(GAFFER_AGENTS, invoked_role + ".md")
    try:
        with open(path, encoding="utf-8") as handle:
            match = ROUTING_COMMENT.search(handle.read())
        routing = json.loads(match.group(1)) if match else None
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    required = (
        "role", "taskGrade", "domainRequirements", "topology",
        "tier", "reasoning", "posture", "composition",
    )
    if (not isinstance(routing, dict) or set(routing) != set(required)
            or routing.get("role") != invoked_role
            or routing.get("role") == "researcher"
            or not SAFE_ROLE.fullmatch(str(routing.get("role", "")))):
        return None
    if not all(isinstance(routing[key], str) for key in (
            "role", "taskGrade", "topology", "tier", "reasoning", "posture")):
        return None
    domains = routing["domainRequirements"]
    if not isinstance(domains, list) or not all(isinstance(item, str) for item in domains):
        return None
    composition = routing["composition"]
    if (not isinstance(composition, dict)
            or not {"kind", "id", "overrides"}.issubset(composition)
            or not set(composition).issubset({"kind", "id", "overrides", "overrideReason"})
            or composition.get("kind") != "preset"
            or composition.get("id") != routing["role"]
            or not isinstance(composition.get("overrides"), list)
            or not all(isinstance(item, str) for item in composition["overrides"])):
        return None
    overrides = composition["overrides"]
    reason = composition.get("overrideReason")
    if ((overrides and (not isinstance(reason, str) or not reason.strip()))
            or (not overrides and "overrideReason" in composition)):
        return None
    return routing

def north_call(d):
    envelope = {
        "prompt": "<paste the same prompt verbatim>",
        "provider": "auto",
        **d,
    }
    return "mcp__north__spawn " + json.dumps(
        envelope, separators=(",", ":"), ensure_ascii=False,
    )

# Was this a gaffer squad pick? If so, translate it to the EXACT north call so
# recovery is a single paste — no re-deriving role->dials by hand every time.
subagent = ""
if tool in ("Agent", "Task"):
    subagent = ti.get("subagent_type") or ti.get("subagentType") or ""
is_gaffer = subagent.lower().startswith("gaffer:")
role_key = subagent.split(":", 1)[1].strip().lower() if is_gaffer else ""
routing = routing_for(role_key) if role_key else None

if routing:
    recipe = (
        "Native " + tool + " (" + subagent + ") is ephemeral — no claim trail, "
        "no steering, no observability. Re-issue the SAME work on north; dials are "
        "read from canonical gaffer:" + role_key + " metadata — just paste your prompt in:\n"
        "  " + north_call(routing) + "\n"
        "Fan-out? fire one mcp__north__spawn per lane in the same turn. "
        "Observe: web :8088. Deliberate bypass: north config dispatch warn|native."
    )
else:
    where = subagent or tool
    recipe = (
        "Native " + tool + " (" + where + ") is ephemeral — no claim trail, no "
        "steering, no observability. Do the SAME work on north:\n"
        "  1. Trivial lookup / single file? No agent at all — bash/grep/read inline.\n"
        "  2. One job: inspect north templates, select a Gaffer template, then "
        "use its generated full "
        "eight-field routing request with mcp__north__spawn; the CLI forcing "
        "form is north spawn <template-id> <prompt>. Override only task grade, "
        "domains, tier, reasoning, or posture, with a reason, while its "
        "responsibility, deliverable, done criteria, report shape, and fixed "
        "topology/capability boundary still match. Any topology/authority "
        "change — or a different responsibility, deliverable, done criteria, "
        "report shape, or capability boundary — requires a complete bespoke "
        "contract. A captured "
        "thread may use mcp__north__dispatch with the same contract.\n"
        "  3. Fan-out: N x mcp__north__spawn in parallel; message workers via "
        "bb ~/code/north/cli/msg-cli.clj 7977 send; observe via web :8088.\n"
        "  Provider resolution and concrete model selection belong to North.\n"
        "Bypass deliberately: north config dispatch warn|native (or /north-config)."
    )

if mode == "warn":
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "additionalContext": "north config dispatch = warn. " + recipe,
    }}
else:
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "DENIED by north config dispatch setting (north). " + recipe,
    }}

print(json.dumps(out))
sys.exit(0)
PYEOF

exec python3 -c "$PY"
