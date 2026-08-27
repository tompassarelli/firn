#!/usr/bin/env bash
# PreToolUse guard — todo attempt and ledger model fields must name the concrete
# runtime model. Parent selection behavior is not itself a model identity.
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

hook_dir="$(dirname "$0")"
if [ -r "$hook_dir/lib/authoring-killswitch.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$hook_dir/lib/authoring-killswitch.sh" 2>/dev/null || true
fi
type authoring_guards_off >/dev/null 2>&1 || exit 0
authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

shopt -s nocasematch
[[ "$payload" =~ model || "$payload" =~ estimate-calibration ]] || exit 0
shopt -u nocasematch

read -r -d '' PY <<'PYEOF' || true
import json
import os
import re
import sys


def allow():
    raise SystemExit(0)


try:
    envelope = json.load(sys.stdin)
except Exception:
    allow()

tool = envelope.get("tool_name") or envelope.get("toolName")
tool_input = envelope.get("tool_input") or envelope.get("toolInput")
if not isinstance(tool_input, dict):
    allow()

cwd = envelope.get("cwd")
if not isinstance(cwd, str) or not cwd:
    cwd = os.getcwd()
todo_root = os.path.realpath(
    os.path.expanduser(os.environ.get("TODO_ROOT", "~/code/todo"))
)


def resolve_path(value):
    if not isinstance(value, str) or not value:
        return None
    home = os.path.expanduser("~")
    value = value.replace("${HOME}", home).replace("$HOME", home)
    value = os.path.expanduser(value)
    if not os.path.isabs(value):
        value = os.path.join(cwd, value)
    return os.path.realpath(os.path.normpath(value))


def is_todo_record(value):
    path = resolve_path(value)
    return bool(
        path
        and os.path.dirname(path) == todo_root
        and path.lower().endswith(".md")
    )


PLACEHOLDER_WORDS = (
    "ambient", "inherit", "inherited", "lineage", "self", "parent",
    "default", "auto", "current", "unobserved",
    "selected", "selection", "available", "best", "highest", "lowest",
    "fallback", "unspecified", "unknown", "pending", "selector",
)
PLACEHOLDER_ALTERNATION = "|".join(map(re.escape, PLACEHOLDER_WORDS))
PLACEHOLDER = re.compile(
    rf"(?<![a-z0-9])(?:{PLACEHOLDER_ALTERNATION})(?![a-z0-9])", re.I
)
ADMITTED_MODEL_IDENTITIES = frozenset({
    "claude-fable-5",
    "claude-opus-4-8",
    "claude-opus-5",
    "claude-sonnet-5",
    "gpt-5",
    "gpt-5.6-luna",
    "gpt-5.6-sol",
    "gpt-5.6-terra",
})
ADMITTED_MODEL_PATTERN = re.compile(
    r"(?<![a-z0-9])(?:"
    + "|".join(
        map(re.escape, sorted(ADMITTED_MODEL_IDENTITIES, key=len, reverse=True))
    )
    + r")(?![a-z0-9])"
)
FIELD = re.compile(r"^\s*(?:reviewer_)?model\s*=\s*(.+)$", re.I)
CALIBRATION_COLON = re.compile(
    r"(?:^|[;|—])\s*((?:reviewer )?model)\s*:\s*([^;|]+)", re.I
)
CALIBRATION_INLINE = re.compile(
    r"(?:^|[;|—])\s*((?:reviewer_)?model)\s*=\s*([^\s;|]+)", re.I
)
CALIBRATION_PROSE_MODEL = re.compile(
    rf"(?m)^[^|\n]*—\s+(?:(?:one|two|three|four)\s+)?"
    rf"(?:{PLACEHOLDER_ALTERNATION})(?:[- ](?:parent|root|model))?(?=\s|$)",
    re.I,
)
CALIBRATION_MODEL_TABLE_HEADERS = {
    "actor",
    "actor / model",
    "account / model",
    "model",
    "model / actor",
    "staffing",
}
MARKDOWN_TABLE_SEPARATOR = re.compile(r"^:?-{3,}:?$")


def markdown_table_columns(line):
    stripped = line.strip()
    if not (stripped.startswith("|") and stripped.endswith("|")):
        return None
    return [column.strip() for column in stripped[1:-1].split("|")]


def markdown_table_separator(columns):
    return bool(
        columns
        and all(MARKDOWN_TABLE_SEPARATOR.fullmatch(column) for column in columns)
    )


def calibration_model_column(columns):
    for index, column in enumerate(columns):
        normalized = " ".join(column.casefold().split())
        if normalized in CALIBRATION_MODEL_TABLE_HEADERS:
            return index
    return None


def first_model_token(value):
    stripped = value.strip()
    return stripped.split(maxsplit=1)[0].strip("`'\",;") if stripped else ""


def concrete_model_identity(value):
    return value in ADMITTED_MODEL_IDENTITIES


def contains_concrete_model_identity(value):
    return bool(ADMITTED_MODEL_PATTERN.search(value))


def calibration_table_has_invalid_identity(text):
    lines = text.splitlines()
    table_model_column = None
    for index, line in enumerate(lines):
        columns = markdown_table_columns(line)
        if columns is None:
            table_model_column = None
            continue
        next_columns = (
            markdown_table_columns(lines[index + 1])
            if index + 1 < len(lines)
            else None
        )
        if markdown_table_separator(next_columns):
            table_model_column = calibration_model_column(columns)
            continue
        if markdown_table_separator(columns):
            continue
        if (
            table_model_column is not None
            and table_model_column < len(columns)
            and PLACEHOLDER.search(columns[table_model_column])
            and not contains_concrete_model_identity(columns[table_model_column])
        ):
            return True
    return False


def line_has_invalid_identity(line, filename):
    if filename == "model-assignment-ledger.md" and line.lstrip().startswith("#"):
        return False
    match = FIELD.search(line)
    if match and not concrete_model_identity(first_model_token(match.group(1))):
        return True
    if filename == "estimate-calibration.md":
        for pattern in (CALIBRATION_COLON, CALIBRATION_INLINE):
            for match in pattern.finditer(line):
                label, value = match.groups()
                token = first_model_token(value)
                if label.casefold().startswith("reviewer") and token.casefold() == "none":
                    continue
                if not concrete_model_identity(token):
                    return True
    if filename == "model-assignment-ledger.md":
        columns = [column.strip() for column in line.split("|")]
        if len(columns) >= 5 and not concrete_model_identity(
            first_model_token(columns[2])
        ):
            return True
    return False


def text_has_invalid_identity(text, path):
    if not isinstance(text, str):
        return False
    if os.path.basename(path) == "estimate-calibration.md":
        if CALIBRATION_PROSE_MODEL.search(text):
            return True
        if calibration_table_has_invalid_identity(text):
            return True
    return any(
        line_has_invalid_identity(line, os.path.basename(path))
        for line in text.splitlines()
    )


def patch_has_invalid_identity(patch):
    current_path = None
    added_lines = []

    def added_lines_have_invalid_identity():
        return bool(
            current_path
            and is_todo_record(current_path)
            and text_has_invalid_identity("\n".join(added_lines), current_path)
        )

    for line in patch.splitlines():
        header = re.match(r"^\*\*\* (?:Add|Update) File:\s*(.+?)\s*$", line)
        if header:
            if added_lines_have_invalid_identity():
                return True
            current_path = header.group(1)
            added_lines = []
            continue
        if line.startswith("*** "):
            if added_lines_have_invalid_identity():
                return True
            current_path = None
            added_lines = []
            continue
        if current_path and is_todo_record(current_path) and line.startswith("+"):
            added_lines.append(line[1:])
    return added_lines_have_invalid_identity()


COMMAND_MODEL = re.compile(
    r"(?<![a-z0-9_])(?:reviewer_)?model\s*=\s*"
    r"(?:\"([^\"]*)\"|'([^']*)'|([a-z0-9._:/-]+))",
    re.I,
)


def command_has_invalid_identity(command):
    return any(
        not concrete_model_identity(next(value for value in match.groups() if value is not None))
        for match in COMMAND_MODEL.finditer(command)
    )


def command_has_invalid_identity_for_target(command, target):
    if command_has_invalid_identity(command):
        return True
    path = resolve_path(target)
    if (
        path
        and os.path.basename(path) == "estimate-calibration.md"
        and (
            text_has_invalid_identity(command, path)
            or re.search(
                r"(?:^|[;'\"|—])\s*(?:model|reviewer model)\s*:\s*"
                rf"[^;\n|]*?(?<![a-z0-9])(?:{PLACEHOLDER_ALTERNATION})"
                r"(?![a-z0-9])",
                command,
                re.I,
            )
        )
    ):
        return True
    return bool(
        path
        and os.path.basename(path) == "model-assignment-ledger.md"
        and any(
            line_has_invalid_identity(line, "model-assignment-ledger.md")
            for line in command.splitlines()
        )
    )


SHELL_OPERATORS = (
    "&>>", "&>", "&&", "||", "|&", ">>", ">|", "<<", "<>",
    ">", "<", ";", "&", "|", "(", ")", "\n",
)
SHELL_CONTROLS = {";", "&&", "||", "&", "\n", "(", ")"}
PIPELINE_OPERATORS = {"|", "|&"}
REDIRECTION_OPERATORS = {">", ">>", ">|", "&>", "&>>", "<", "<<", "<>"}
WRITE_REDIRECTIONS = {">", ">>", ">|", "&>", "&>>"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$", re.S)


def shell_tokens(source):
    tokens = []
    buffer = []
    started = False
    static = True
    index = 0

    def flush():
        nonlocal buffer, started, static
        if started:
            tokens.append(("word", "".join(buffer), static))
        buffer = []
        started = False
        static = True

    while index < len(source):
        character = source[index]
        if character in " \t\r":
            flush()
            index += 1
            continue
        if character == "#" and not started:
            flush()
            newline = source.find("\n", index)
            if newline < 0:
                break
            tokens.append(("operator", "\n", True))
            index = newline + 1
            continue
        operator = next(
            (candidate for candidate in SHELL_OPERATORS if source.startswith(candidate, index)),
            None,
        )
        if operator is not None:
            flush()
            tokens.append(("operator", operator, True))
            index += len(operator)
            continue
        if character == "\\":
            if index + 1 >= len(source):
                return None
            started = True
            buffer.append(source[index + 1])
            index += 2
            continue
        if character == "'":
            end = source.find("'", index + 1)
            if end < 0:
                return None
            started = True
            buffer.append(source[index + 1:end])
            index = end + 1
            continue
        if character == '"':
            started = True
            index += 1
            while index < len(source) and source[index] != '"':
                if source[index] == "\\":
                    if index + 1 >= len(source):
                        return None
                    buffer.append(source[index + 1])
                    index += 2
                    continue
                if source[index] in "$`":
                    static = False
                buffer.append(source[index])
                index += 1
            if index >= len(source):
                return None
            index += 1
            continue
        if source.startswith("$(", index) or character == "`":
            return None
        if character == "$":
            static = False
        started = True
        buffer.append(character)
        index += 1
    flush()
    return tokens


def split_tokens(tokens, separators):
    groups = []
    current = []
    for token in tokens:
        if token[0] == "operator" and token[1] in separators:
            if current:
                groups.append(current)
                current = []
        else:
            current.append(token)
    if current:
        groups.append(current)
    return groups


def parse_stage(stage):
    words = []
    write_targets = []
    index = 0
    while index < len(stage):
        kind, value, static = stage[index]
        if kind == "operator":
            if value not in REDIRECTION_OPERATORS:
                return None
            if index + 1 >= len(stage) or stage[index + 1][0] != "word":
                return None
            if value in WRITE_REDIRECTIONS:
                write_targets.append(stage[index + 1][1])
            index += 2
            continue
        words.append((value, static))
        index += 1
    while words and ASSIGNMENT.fullmatch(words[0][0]):
        words.pop(0)
    return words, write_targets


def static_shell_scripts(command_name, arguments):
    if command_name not in {"bash", "sh"}:
        return []
    index = 0
    while index < len(arguments):
        value, _ = arguments[index]
        if value == "--":
            return []
        if not value.startswith("-") or value == "-":
            return []
        flags = value[1:]
        if "c" in flags:
            if index + 1 >= len(arguments):
                return []
            script, static = arguments[index + 1]
            return [script] if static else []
        if value in {"-o", "-O"}:
            index += 2
        else:
            index += 1
    return []


def sed_substitution_replacements(script):
    stripped = script.lstrip()
    if len(stripped) < 4 or stripped[0] != "s":
        return []
    delimiter = stripped[1]
    if delimiter.isalnum() or delimiter.isspace() or delimiter == "\\":
        return []

    parts = []
    buffer = []
    escaped = False
    for character in stripped[2:]:
        if escaped:
            buffer.append(character)
            escaped = False
            continue
        if character == "\\":
            escaped = True
            continue
        if character == delimiter:
            parts.append("".join(buffer))
            buffer = []
            if len(parts) == 2:
                return [parts[1]]
            continue
        buffer.append(character)
    return []


def group_has_invalid_identity(group, target):
    group_text = " ".join(token[1] for token in group if token[0] == "word")
    if command_has_invalid_identity_for_target(group_text, target):
        return True
    path = resolve_path(target)
    return bool(
        path
        and any(
            text_has_invalid_identity(token[1], path)
            for token in group
            if token[0] == "word"
        )
    )


def bash_writes_invalid_identity(command, depth=0):
    if depth > 4:
        return False
    tokens = shell_tokens(command)
    if tokens is None:
        return False
    for group in split_tokens(tokens, SHELL_CONTROLS):
        stages = split_tokens(group, PIPELINE_OPERATORS)
        parsed_stages = [parse_stage(stage) for stage in stages]
        if any(parsed is None for parsed in parsed_stages):
            continue
        for stage, (words, write_targets) in zip(stages, parsed_stages):
            for target in write_targets:
                if is_todo_record(target) and group_has_invalid_identity(stage, target):
                    return True
            if not words:
                continue
            command_name = os.path.basename(words[0][0])
            arguments = words[1:]
            for script in static_shell_scripts(command_name, arguments):
                if bash_writes_invalid_identity(script, depth + 1):
                    return True
            if command_name == "apply_patch" and patch_has_invalid_identity(command):
                return True
            if command_name == "tee":
                for candidate, _ in arguments:
                    if (
                        not candidate.startswith("-")
                        and is_todo_record(candidate)
                        and group_has_invalid_identity(group, candidate)
                    ):
                        return True
            if command_name not in {"sed", "perl"}:
                continue
            argument_values = [value for value, _ in arguments]
            in_place = any(
                candidate == "-i"
                or candidate.startswith("-i")
                or candidate == "--in-place"
                or candidate.startswith("--in-place=")
                or (
                    command_name == "perl"
                    and candidate.startswith("-p")
                    and "i" in candidate
                )
                for candidate in argument_values
            )
            written_text = (
                [
                    replacement
                    for argument in argument_values
                    for replacement in sed_substitution_replacements(argument)
                ]
                if command_name == "sed"
                else [" ".join(argument_values)]
            )
            if in_place and any(
                is_todo_record(candidate)
                and any(
                    command_has_invalid_identity_for_target(text, candidate)
                    for text in written_text
                )
                for candidate in argument_values
            ):
                return True
    return False


hit = False
if tool in {"Edit", "Write", "MultiEdit"}:
    path = tool_input.get("file_path") or tool_input.get("filePath")
    if not is_todo_record(path):
        allow()
    if tool == "Write":
        values = [tool_input.get("content")]
    elif tool == "Edit":
        values = [tool_input.get("new_string") or tool_input.get("newString")]
    else:
        edits = tool_input.get("edits")
        if not isinstance(edits, list):
            allow()
        values = [
            edit.get("new_string") or edit.get("newString")
            for edit in edits
            if isinstance(edit, dict)
        ]
    hit = any(text_has_invalid_identity(value, path) for value in values)
elif tool == "apply_patch":
    patch = tool_input.get("input")
    if not isinstance(patch, str):
        allow()
    hit = patch_has_invalid_identity(patch)
elif tool == "Bash":
    command = tool_input.get("command")
    if not isinstance(command, str):
        allow()
    hit = bash_writes_invalid_identity(command)
else:
    allow()

if not hit:
    allow()

reason = (
    "BLOCKED: a todo model field must name an exact concrete runtime model, "
    "not a selection or lineage placeholder. "
    "Record the exact concrete model from run or dispatch evidence "
    "(for example `gpt-5.6-sol`); if that evidence is unavailable, record the "
    "evidence gap outside the model field instead of inventing an identity."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
PYEOF

printf '%s' "$payload" | python3 -c "$PY" 2>/dev/null || exit 0
