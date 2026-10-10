#!/usr/bin/env bash
# PreToolUse guard — refuses slow tree searches and names the exact modern
# replacement: recursive `grep -r` becomes `rg`, and a `find` tree search by
# name, path or type becomes `fd`.
#
# Only command-position invocations count: pipes, `&&`, `;`, wrappers and
# `bash -c` payloads are decoded, while quoted arguments (a commit message) and
# heredoc bodies are inert. Allowed: non-recursive grep (a pipe or named
# files), `git grep`, recursive grep over named regular files, `find` with
# `-maxdepth` 0 or 1, `find` without a name/path/type test, and any `find`
# using a test or action fd cannot express exactly (`-mtime`, `-prune`,
# `-delete`, `!`, `-o` beyond an extension list, ...).
#
# Kill-switch: persistent `north config agents off modern-search-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces guards live).
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

[ "$payload_oversized" -eq 0 ] || exit 0

case "$payload" in
  *grep*|*find*) ;;
  *) exit 0 ;;
esac

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || exit 0
type authoring_guards_off >/dev/null 2>&1 || exit 0
authoring_guards_off && exit 0

python_bin="${NORTH_AGENT_PYTHON:-python3}"

read -r -d '' PY <<'PYEOF' || true
import json
import os
import re
import shlex
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
    sys.exit(65)


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


SEPARATORS = {";", "&", "|", "\n", "`"}


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
            quoted = True
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
        if char == ")" or (char == "(" and (not buffer or buffer[-1] == "$")):
            if buffer and buffer[-1] == "$" and char == "(":
                buffer.pop()
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


GREP_LIKE = {"grep", "egrep", "fgrep"}
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
SAFE_WORD = re.compile(r"[A-Za-z0-9_@%+=:,./~${}-]+")


def render(words):
    return " ".join(
        word if SAFE_WORD.fullmatch(word) else shlex.quote(word)
        for word in words
    )


class Untranslatable(Exception):
    pass


# --- grep -r -> rg ---------------------------------------------------------

GREP_SHORT_SAME = set("nilcvwxoqHFPab")
GREP_SHORT_MAP = {"h": "-I", "L": "--files-without-match", "y": "-i",
                  "Z": "-0", "R": "-L"}
GREP_SHORT_DROP = set("rEGIsUT")
GREP_SHORT_VALUED = set("efmABCdD")
GREP_LONG_FLAGS = {
    "--line-number": "-n", "--ignore-case": "-i", "--files-with-matches": "-l",
    "--files-without-match": "--files-without-match", "--count": "-c",
    "--invert-match": "-v", "--word-regexp": "-w", "--line-regexp": "-x",
    "--only-matching": "-o", "--quiet": "-q", "--silent": "-q",
    "--with-filename": "-H", "--no-filename": "-I", "--fixed-strings": "-F",
    "--perl-regexp": "-P", "--text": "-a", "--null": "-0",
    "--byte-offset": "-b", "--dereference-recursive": "-L",
    "--recursive": None, "--extended-regexp": None, "--basic-regexp": None,
    "--no-messages": None, "--initial-tab": None, "--binary": None,
    "--color": None, "--colour": None,
}
GREP_LONG_VALUED = {
    "--regexp", "--file", "--max-count", "--after-context",
    "--before-context", "--context", "--include", "--exclude",
    "--exclude-dir", "--binary-files", "--label", "--devices",
    "--directories", "--exclude-from", "--group-separator",
}
GREP_VALUE_TARGET = {
    "e": "-e", "f": "-f", "m": "-m", "A": "-A", "B": "-B", "C": "-C",
    "--regexp": "-e", "--file": "-f", "--max-count": "-m",
    "--after-context": "-A", "--before-context": "-B", "--context": "-C",
}


def grep_to_rg(arguments, base):
    recursive = False
    flags = []          # single-letter rg flags, merged into one group
    options = []        # other rg options, in order
    operands = []
    explicit_pattern = False

    def value_option(name, value):
        nonlocal explicit_pattern
        if name in ("e", "f", "--regexp", "--file"):
            explicit_pattern = True
        target = GREP_VALUE_TARGET.get(name)
        if target:
            options.extend([target, value])
        elif name == "--include":
            options.extend(["-g", value])
        elif name in ("--exclude", "--exclude-dir"):
            options.extend(["-g", "!" + value])
        elif name in ("--label", "--group-separator", "--exclude-from"):
            raise Untranslatable()

    index = 0
    while index < len(arguments):
        argument = arguments[index]
        index += 1
        if argument == "--":
            operands.extend(arguments[index:])
            break
        if argument.startswith("--"):
            name, has_value, value = argument.partition("=")
            if name in ("--recursive", "--dereference-recursive"):
                recursive = True
            if name in GREP_LONG_VALUED:
                if not has_value:
                    if index >= len(arguments):
                        raise Untranslatable()
                    value = arguments[index]
                    index += 1
                value_option(name, value)
                continue
            if name in GREP_LONG_FLAGS:
                mapped = GREP_LONG_FLAGS[name]
                if mapped and len(mapped) == 2:
                    flags.append(mapped[1])
                elif mapped:
                    options.append(mapped)
                continue
            raise Untranslatable()
        if argument.startswith("-") and len(argument) > 1:
            if re.fullmatch(r"-[0-9]+", argument):
                options.extend(["-C", argument[1:]])
                continue
            group = argument[1:]
            position = 0
            while position < len(group):
                letter = group[position]
                position += 1
                if letter in ("r", "R"):
                    recursive = True
                if letter in GREP_SHORT_VALUED:
                    value = group[position:]
                    if not value:
                        if index >= len(arguments):
                            raise Untranslatable()
                        value = arguments[index]
                        index += 1
                    value_option(letter, value)
                    break
                if letter in GREP_SHORT_SAME:
                    flags.append(letter)
                elif letter in GREP_SHORT_MAP:
                    mapped = GREP_SHORT_MAP[letter]
                    if len(mapped) == 2:
                        flags.append(mapped[1])
                    else:
                        options.append(mapped)
                elif letter not in GREP_SHORT_DROP:
                    raise Untranslatable()
            continue
        operands.append(argument)

    if not recursive:
        return None
    if not explicit_pattern:
        if not operands:
            return None
        pattern, paths = operands[0], operands[1:]
    else:
        pattern, paths = None, operands
    # Recursion over named regular files walks nothing.
    if paths and all(os.path.isfile(os.path.join(base, os.path.expanduser(path)))
                     for path in paths):
        return None
    words = ["rg"]
    unique = []
    for letter in flags:
        if letter not in unique:
            unique.append(letter)
    if unique:
        words.append("-" + "".join(unique))
    words.extend(options)
    if pattern is not None:
        if pattern.startswith("-"):
            words.extend(["-e", pattern])
        else:
            words.append(pattern)
    words.extend(paths)
    return words


# --- find -> fd ------------------------------------------------------------

FIND_GLOBAL = {"-H", "-P", "-O0", "-O1", "-O2", "-O3"}
EXTENSION = re.compile(r"\*\.([A-Za-z0-9_+-]+)")
GLOB_META = re.compile(r"[*?\[]")


def name_terms(kind, pattern, fd_options):
    """Translate one -name/-iname/-path test into fd options; returns pattern."""
    if kind in ("-name", "-iname"):
        if "/" in pattern:
            raise Untranslatable()
        if kind == "-iname":
            fd_options.append("-i")
        if pattern.startswith("."):
            fd_options.append("-H")
        match = EXTENSION.fullmatch(pattern)
        if match:
            fd_options.extend(["-e", match.group(1)])
            return None
        fd_options.append("-g")
        return pattern
    # -path/-ipath: find's '*' crosses '/', fd's does not, and fd matches the
    # absolute path. Only '*/dir/.../last' maps exactly, as '**/dir/.../last'.
    parts = pattern.split("/")
    if len(parts) < 2 or parts[0] != "*" or any(
            not part or GLOB_META.search(part) for part in parts[1:-1]):
        raise Untranslatable()
    last = parts[-1]
    if last == "*":
        last = "**"
    elif GLOB_META.search(last):
        last = "**/" + last
    elif not last:
        raise Untranslatable()
    if kind == "-ipath":
        fd_options.append("-i")
    fd_options.extend(["-p", "-g"])
    return "/".join(["**"] + parts[1:-1] + [last])


def find_to_fd(arguments):
    index = 0
    fd_options = []
    while index < len(arguments) and arguments[index] in FIND_GLOBAL | {"-L"}:
        if arguments[index] == "-L":
            fd_options.append("-L")
        index += 1
    roots = []
    while index < len(arguments) and not (
            arguments[index].startswith("-") or arguments[index] in ("(", "!", ")")):
        roots.append(arguments[index])
        index += 1
    expression = arguments[index:]

    searching = False
    max_depth = None
    pattern = None
    extensions_from_or = []
    top_level_or = False
    executor = []

    position = 0
    while position < len(expression):
        token = expression[position]
        position += 1

        def take():
            nonlocal position
            if position >= len(expression):
                raise Untranslatable()
            value = expression[position]
            position += 1
            return value

        if token == "(":
            # Only an OR list of extension globs is expressible:
            # \( -name '*.a' -o -name '*.b' \).
            if ")" not in expression[position:]:
                raise Untranslatable()
            closing = expression.index(")", position)
            group = expression[position:closing]
            position = closing + 1
            if len(group) < 5 or (len(group) + 1) % 3:
                raise Untranslatable()
            for start in range(0, len(group), 3):
                kind, value = group[start], group[start + 1]
                match = EXTENSION.fullmatch(value)
                if kind != "-name" or not match:
                    raise Untranslatable()
                if start + 2 < len(group) and group[start + 2] not in ("-o", "-or"):
                    raise Untranslatable()
                extensions_from_or.append(match.group(1))
            searching = True
            continue
        if token in ("-name", "-iname", "-path", "-ipath", "-wholename"):
            kind = "-path" if token == "-wholename" else token
            # find -name a -o -name b at top level: extension lists only.
            value = take()
            if position < len(expression) and expression[position] in ("-o", "-or"):
                match = EXTENSION.fullmatch(value)
                if kind != "-name" or not match:
                    raise Untranslatable()
                extensions_from_or.append(match.group(1))
                position += 1
                top_level_or = True
                searching = True
                continue
            if top_level_or:
                match = EXTENSION.fullmatch(value)
                if kind != "-name" or not match:
                    raise Untranslatable()
                extensions_from_or.append(match.group(1))
                searching = True
                continue
            if pattern is not None:
                raise Untranslatable()
            translated = name_terms(kind, value, fd_options)
            pattern = translated if translated is not None else pattern
            searching = True
            continue
        if token == "-type":
            for kind in take().split(","):
                mapped = {"f": "f", "d": "d", "l": "l", "s": "s", "p": "p"}.get(kind)
                if not mapped:
                    raise Untranslatable()
                fd_options.extend(["-t", mapped])
            searching = True
            continue
        if token == "-maxdepth":
            value = take()
            if not value.isdigit():
                raise Untranslatable()
            max_depth = int(value)
            continue
        if token == "-mindepth":
            value = take()
            if not value.isdigit():
                raise Untranslatable()
            fd_options.extend(["--min-depth", value])
            continue
        if token == "-empty":
            fd_options.extend(["-t", "e"])
            searching = True
            continue
        if token in ("-xdev", "-mount"):
            fd_options.append("--one-file-system")
            continue
        if token == "-print0":
            fd_options.append("-0")
            continue
        if token in ("-print", "-a", "-and", "-follow"):
            if token == "-follow":
                fd_options.append("-L")
            continue
        if token == "-exec":
            command_words = []
            while True:
                word = take()
                if word in (";", "+"):
                    break
                command_words.append(word)
            if not command_words or executor:
                raise Untranslatable()
            if word == "+":
                if command_words[-1] != "{}":
                    raise Untranslatable()
                executor = ["-X"] + command_words[:-1]
            else:
                executor = ["-x"] + command_words
            continue
        raise Untranslatable()

    if max_depth is not None and max_depth <= 1:
        return None
    # find binds AND tighter than a bare top-level -o; fd cannot express that.
    if top_level_or and (pattern is not None or executor or any(
            option in ("-t", "-g") for option in fd_options)):
        raise Untranslatable()
    if not searching:
        return None
    if max_depth is not None:
        fd_options.extend(["-d", str(max_depth)])
    for extension in extensions_from_or:
        fd_options.extend(["-e", extension])

    words = ["fd"]
    seen_flags = set()
    for option in fd_options:
        if option in ("-i", "-H", "-L", "-0", "-p", "--one-file-system"):
            if option in seen_flags:
                continue
            seen_flags.add(option)
        words.append(option)
    # fd takes one pattern before its paths; "." matches every name.
    if "-g" in words:
        words.remove("-g")
        tail_pattern = ["-g", pattern]
    else:
        tail_pattern = [pattern] if pattern is not None else []
    paths = list(roots)
    if paths == ["."]:
        paths = []
    if tail_pattern:
        words.extend(tail_pattern)
    elif paths:
        words.append(".")
    words.extend(paths)
    words.extend(executor)
    return words


def inspect_segment(words, base, depth):
    if not words or depth > 3:
        return None
    index = 0
    while index < len(words) and (ASSIGNMENT.fullmatch(words[index][0])
                                  or words[index][0] in ("{", "}", "!")):
        index += 1
    while index < len(words):
        text, quoted = words[index]
        executable = os.path.basename(text)
        if executable in SHELLS:
            for option_index in range(index + 1, len(words)):
                option = words[option_index][0]
                if option.startswith("-") and "c" in option[1:]:
                    command_index = option_index + 1
                    while command_index < len(words) and words[command_index][0] == "--":
                        command_index += 1
                    if command_index < len(words):
                        return inspect_command(words[command_index][0], base, depth + 1)
                    return None
            return None
        if executable == "eval":
            return inspect_command(" ".join(word for word, _ in words[index + 1:]),
                                   base, depth + 1)
        arguments = [word for word, _ in words[index + 1:]]
        if executable in GREP_LIKE or executable == "rgrep":
            if executable == "rgrep":
                arguments = ["-r"] + arguments
            try:
                replacement = grep_to_rg(arguments, base)
            except Untranslatable:
                return None
            if replacement:
                return text, render([text] + arguments), render(replacement)
            return None
        if executable == "find":
            try:
                replacement = find_to_fd(arguments)
            except Untranslatable:
                return None
            if replacement:
                return text, render([text] + arguments), render(replacement)
            return None
        if executable not in WRAPPERS:
            return None
        if executable in ("command", "builtin") and any(
                option in ("-v", "-V") for option, _ in words[index + 1:]):
            return None
        index += 1
        while index < len(words):
            token = words[index][0]
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
    for kind, value, quoted in tokenize(strip_heredocs(text)):
        if kind == "sep":
            hit = inspect_segment(segment, base, depth)
            if hit:
                return hit
            segment = []
        else:
            segment.append((value, quoted))
    return inspect_segment(segment, base, depth)


hit = inspect_command(command, cwd)
if not hit:
    allow()

tool, original, replacement = hit
if tool.endswith("find"):
    slow = "a `find` tree search"
    hidden = "fd skips hidden and git-ignored files; add -H and/or -I when you need them."
else:
    slow = "a recursive grep"
    hidden = "rg skips hidden and git-ignored files; add --hidden or -uu when you need them."
reason = (
    f"BLOCKED: `{original}` is {slow}; use the modern tool instead: "
    f"`{replacement}`. {hidden} "
    "Defaults: rg for content search, fd for finding files, ast-grep for "
    "structural code search, sd for simple replacements, jq/yq for JSON/YAML."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
PYEOF

hook_decide "$python_bin" -c "$PY"
