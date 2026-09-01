#!/usr/bin/env bash
# PreToolUse guard — refuses recursive or fan-out search through Linux
# kernel/runtime virtual roots and repository container roots. Virtual trees
# expose dynamic metadata, device streams, and symlink edges into arbitrary
# filesystems; repository containers fan one search into main plus every lane.
#
# This identity owns /proc, /sys, /dev, /run and the /var/run,/var/lock aliases,
# plus repository roots containing main/ and worktrees/. corpus-scan-guard
# remains the sole transcript-corpus authority. Ordinary search inside one
# checkout, subtree, exact file, or bounded data root stays allowed.
set -uo pipefail

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

# The activity gate and its runtime are optional inputs. Any missing or invalid
# dependency disables this guard rather than turning an internal failure into a
# provider-wide tool outage.
# shellcheck disable=SC1090,SC1091
authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
. "$authoring_killswitch" 2>/dev/null || exit 0
type authoring_guards_off >/dev/null 2>&1 || exit 0
authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

search_command_re='(^|[^[:alnum:]_.-])(rg|ripgrep|ag|ack|ack-grep|fd|fdfind|grep|egrep|fgrep|zgrep|zegrep|zfgrep|rgrep)([[:space:]]|$)'
[[ "$payload" =~ $search_command_re ]] || exit 0

python_bin="${NORTH_AGENT_PYTHON:-python3}"
command -v -- "$python_bin" >/dev/null 2>&1 || exit 0

read -r -d '' PY <<'PYEOF' || true
import json
import os
import re
import stat
import sys


def allow():
    raise SystemExit(0)


try:
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        allow()
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        allow()
    command = tool_input.get("command")
    if not isinstance(command, str) or not command:
        allow()
    cwd = data.get("cwd") or os.getcwd()
    if not isinstance(cwd, str):
        allow()
except (Exception, SystemExit) as error:
    if isinstance(error, SystemExit):
        raise
    allow()


HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_heredocs(text):
    out = []
    offset = 0
    while offset < len(text):
        match = HEREDOC.search(text, offset)
        if not match:
            out.append(text[offset:])
            break
        out.append(text[offset:match.end()])
        line_end = text.find("\n", match.end())
        if line_end < 0:
            out.append(text[match.end():])
            break
        out.append(text[match.end():line_end + 1])
        terminator = re.compile(
            r"^[ \t]*" + re.escape(match.group(2)) + r"[ \t]*$", re.MULTILINE
        )
        end = terminator.search(text, line_end + 1)
        body_end = end.start() if end else len(text)
        out.append("".join("\n" if char == "\n" else " "
                           for char in text[line_end + 1:body_end]))
        offset = body_end
    return "".join(out)


SEPARATORS = {";", "&", "|", "\n", "(", ")", "`"}


def tokenize(text):
    tokens = []
    buffer = []
    quoted = False
    index = 0

    def flush():
        nonlocal buffer, quoted
        if buffer:
            tokens.append(("word", "".join(buffer), quoted))
        buffer = []
        quoted = False

    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            buffer.append(text[index + 1])
            index += 2
            continue
        if char == "'":
            end = text.find("'", index + 1)
            end = len(text) if end < 0 else end
            buffer.append(text[index + 1:end])
            quoted = True
            index = end + 1
            continue
        if char == '"':
            cursor = index + 1
            piece = []
            while cursor < len(text):
                if text[cursor] == "\\" and cursor + 1 < len(text):
                    piece.append(text[cursor + 1])
                    cursor += 2
                    continue
                if text[cursor] == '"':
                    break
                piece.append(text[cursor])
                cursor += 1
            buffer.append("".join(piece))
            quoted = True
            index = cursor + 1
            continue
        if char in SEPARATORS:
            flush()
            tokens.append(("sep", char, False))
            index += 1
            continue
        if char in " \t\r":
            flush()
            index += 1
            continue
        buffer.append(char)
        index += 1
    flush()
    return tokens


ALWAYS_RECURSIVE = {
    "rg", "ripgrep", "ag", "ack", "ack-grep", "fd", "fdfind",
}
GREP_LIKE = {"grep", "egrep", "fgrep", "zgrep", "zegrep", "zfgrep"}
SEARCH_TOOLS = ALWAYS_RECURSIVE | GREP_LIKE | {"rgrep"}
WRAPPERS = {
    "sudo", "doas", "env", "nice", "ionice", "time", "nohup", "command",
    "builtin", "exec", "xargs", "timeout", "stdbuf", "setsid",
}
WRAPPER_VALUES = {
    "-u", "--user", "-g", "--group", "-n", "--adjustment", "-c", "-e",
    "-I", "--replace", "-P", "--max-procs", "-L", "--max-lines", "-s",
    "--signal", "-k", "--kill-after", "-o", "--output", "-i", "--input",
}
SHELLS = {"bash", "sh", "dash", "zsh", "ksh"}
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*", re.DOTALL)


def recursive_grep(arguments):
    for argument in arguments:
        if argument in ("-r", "-R", "--recursive", "--dereference-recursive"):
            return True
        if re.fullmatch(r"-[A-Za-z]+", argument) and (
                "r" in argument[1:] or "R" in argument[1:]):
            return True
    return False


VALUED_OPTIONS = {
    "-e", "--regexp", "-f", "--file", "-m", "--max-count", "-A",
    "--after-context", "-B", "--before-context", "-C", "--context", "-d",
    "--directories", "-D", "--devices", "--include", "--exclude",
    "--exclude-dir", "--exclude-from", "--binary-files", "--color",
    "--colour", "--label", "--group-separator", "-g", "--glob", "--iglob",
    "-t", "--type", "-T", "--type-not", "--replace", "--max-depth",
    "--max-filesize", "--sort", "--sortr", "-j", "--threads", "--pre",
    "--ignore-file", "-E", "--encoding", "--path-separator",
}


def path_operands(tool, arguments, piped_stdin=False):
    informational = {
        "--help", "--version", "--type-list", "--pcre2-version", "--generate",
    }
    if any(argument.split("=", 1)[0] in informational for argument in arguments):
        return None
    if tool in GREP_LIKE and not recursive_grep(arguments):
        return None
    words = []
    skip = False
    explicit_pattern = False
    files_mode = False
    for index, argument in enumerate(arguments):
        if skip:
            skip = False
            continue
        if argument == "--":
            words.extend(arguments[index + 1:])
            break
        option = argument.split("=", 1)[0] if argument.startswith("-") else argument
        if option in ("-e", "--regexp", "-f", "--file"):
            explicit_pattern = True
        if option == "--files":
            files_mode = True
        if argument.startswith("-") and argument != "-":
            if "=" not in argument and option in VALUED_OPTIONS:
                skip = True
            continue
        words.append(argument)
    if not explicit_pattern and not files_mode and words:
        words = words[1:]
    explicit_stdin = not files_mode and "-" in words
    if explicit_stdin:
        words = [word for word in words if word != "-"]
    pattern_from_stdin = any(
        (argument in ("-f", "--file")
         and index + 1 < len(arguments)
         and arguments[index + 1] == "-")
        or argument == "--file=-"
        for index, argument in enumerate(arguments)
    )
    if words:
        return words
    if explicit_stdin or (piped_stdin and not files_mode and not pattern_from_stdin):
        return []
    return ["."]


GLOB_META = re.compile(r"[*?\[{]")
PROC_LINK = re.compile(
    r"^/proc/[^/]+/(?:cwd|root|exe)(?:/|$)|"
    r"^/proc/[^/]+/(?:fd|map_files)/[^/]+(?:/|$)"
)


def resolve_operand(operand, base):
    path = operand
    home = os.path.expanduser("~")
    if path == "~":
        path = home
    elif path.startswith("~/"):
        path = home + path[1:]
    path = path.replace("${HOME}", home).replace("$HOME", home)
    if not path.startswith("/"):
        path = os.path.join(base, path)
    path = os.path.normpath(path)
    if path == "/var/run" or path.startswith("/var/run/"):
        path = "/run" + path[len("/var/run"):]
    elif path == "/var/lock" or path.startswith("/var/lock/"):
        path = "/run/lock" + path[len("/var/lock"):]
    return path


def virtual_root(path):
    for root in ("/proc", "/sys", "/dev", "/run"):
        if path == root or path.startswith(root + "/"):
            return root
    return None


def dangerous_virtual_operand(paths, base):
    virtual = []
    for operand in paths:
        path = resolve_operand(operand, base)
        root = virtual_root(path)
        if root:
            virtual.append((operand, path, root))
    if len(virtual) > 1:
        return virtual[0][1], "fan-out across multiple virtual-root operands"
    for operand, path, root in virtual:
        if GLOB_META.search(operand) or GLOB_META.search(path):
            return path, "shell-expanded or wildcard virtual-root traversal"
        if path == root:
            return path, "recursive traversal from a virtual filesystem root"
        if PROC_LINK.search(path):
            return path, "recursive traversal through process metadata symlinks"
        try:
            mode = os.lstat(path).st_mode
        except (OSError, ValueError):
            continue
        if stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
            return path, "recursive traversal through a virtual directory or symlink"
        if not stat.S_ISREG(mode):
            return path, "content search over a virtual device or special file"
    return None


def dangerous_repository_container(paths, base):
    for operand in paths:
        path = resolve_operand(operand, base)
        try:
            is_container = (
                os.path.isdir(os.path.join(path, "main"))
                and os.path.isdir(os.path.join(path, "worktrees"))
            )
        except (OSError, ValueError):
            continue
        if is_container:
            return path, "recursive search rooted at a repository container"
    return None


def inspect_segment(words, base, depth, piped_stdin=False):
    if not words or depth > 3:
        return None
    index = 0
    while index < len(words) and (ASSIGNMENT.fullmatch(words[index])
                                  or words[index] in ("{", "}")):
        index += 1
    while index < len(words):
        executable = os.path.basename(words[index])
        if executable in SHELLS:
            for option_index in range(index + 1, len(words)):
                option = words[option_index]
                if option.startswith("-") and "c" in option[1:]:
                    command_index = option_index + 1
                    while command_index < len(words) and words[command_index] == "--":
                        command_index += 1
                    if command_index < len(words):
                        return inspect_command(words[command_index], base, depth + 1)
                    return None
            return None
        if executable == "eval":
            return inspect_command(" ".join(words[index + 1:]), base, depth + 1)
        if executable in SEARCH_TOOLS:
            operands = path_operands(executable, words[index + 1:], piped_stdin)
            if operands is None:
                return None
            hit = dangerous_virtual_operand(operands, base)
            if hit:
                return executable, hit[0], hit[1], "virtual"
            hit = dangerous_repository_container(operands, base)
            if hit:
                return executable, hit[0], hit[1], "repository"
            return None
        if executable not in WRAPPERS:
            return None
        if executable in ("command", "builtin") and any(
                option in ("-v", "-V") for option in words[index + 1:]):
            return None
        index += 1
        while index < len(words):
            token = words[index]
            if ASSIGNMENT.fullmatch(token) or re.fullmatch(r"[0-9]+(?:ms|s|m|h|d)?", token):
                index += 1
                continue
            if token == "--":
                index += 1
                break
            if token.startswith("-"):
                option = token.split("=", 1)[0]
                index += 2 if "=" not in token and option in WRAPPER_VALUES else 1
                continue
            break
    return None


def inspect_command(text, base, depth=0):
    segment = []
    piped_stdin = False
    for kind, value, _quoted in tokenize(strip_heredocs(text)):
        if kind == "sep":
            hit = inspect_segment(segment, base, depth, piped_stdin)
            if hit:
                return hit
            segment = []
            piped_stdin = value == "|"
        else:
            segment.append(value)
    return inspect_segment(segment, base, depth, piped_stdin)


try:
    hit = inspect_command(command, cwd)
except Exception:
    allow()
if not hit:
    allow()

tool, target, shape, scope = hit
if scope == "repository":
    reason = (
        f"BLOCKED: `{tool}` would perform {shape} at {target}, traversing main "
        "and every worktree. Select one exact checkout or subtree first, then "
        "run the scoped search there (for example, `rg --files "
        f"{target}/main`)."
    )
else:
    reason = (
        f"BLOCKED: `{tool}` would perform {shape} at {target}. "
        "Do not use recursive content search over /proc, /sys, /dev, or /run. "
        "Select one process with `ps -eo pid=,comm=,args=` (or `ps -p PID -o ...`) "
        "and query only the needed metadata, for example "
        "`readlink -e /proc/PID/cwd`. Use `cat` or `stat` for one known metadata "
        "file. If the resolved cwd contains the content of interest, run ordinary "
        "scoped `rg` on that filesystem path instead."
    )
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
PYEOF

printf '%s' "$payload" | "$python_bin" -c "$PY" || exit 0
