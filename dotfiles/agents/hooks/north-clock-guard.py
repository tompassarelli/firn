#!/usr/bin/env python3
"""Provider-neutral human client-session admission core.

The shell wrapper owns the explicit authoring kill-switch and launches this
file with an attested Python interpreter. This core is total over the supported
Claude/Codex hook envelopes: it emits a private allow/not-applicable
attestation when requested, a protocol-valid denial for a missing/mismatched
client session, or the stable infrastructure denial when admission cannot be
proved. Managed-agent run telemetry is deliberately orthogonal: it measures
task execution but never authorizes or bills client work.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from glob import glob
from collections.abc import Iterable


MAX_INPUT_BYTES = 1 << 20
MAX_PATH_EXPANSIONS = 128
CLIENT_RE = re.compile(
    r"/code/client/([A-Za-z0-9][A-Za-z0-9._-]*)(?:/|$)"
)
CLIENT_ROOT = "/code/client/"
CLIENT_NAMESPACE_RE = re.compile(r"/code/client(?:/|$)")
SIMPLE_VARIABLE_RE = re.compile(
    r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))"
)
GUARDED_NONCLIENT_PATH_WORD_RE = re.compile(
    r"(?:(?P<option>--prefix=))?"
    r"\$\{(?P<name>[A-Za-z_][A-Za-z0-9_]*):\?\}"
    r"(?P<suffix>(?:/[A-Za-z0-9._+,:=@%~-]+)*/?)"
)
GUARDED_EMPTY_EXPANSION_RE = re.compile(
    r"\$\{[A-Za-z_][A-Za-z0-9_]*:\?\}"
)
LITERAL_ABSOLUTE_PATH_RE = re.compile(r"/[A-Za-z0-9._+,:=@%~/-]+")
LITERAL_SCRATCH_ROOTS = ("/tmp", "/var/tmp")
ASSIGNMENT_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
SAFE_SET_PREAMBLE_RE = re.compile(
    r"\A[ \t]*set"
    r"(?P<arguments>(?:[ \t]+(?:-[A-Za-z]+|[A-Za-z]+))+?)"
    r"[ \t]*(?:;|\n)[ \t]*"
)
SAFE_MKTEMP_ASSIGNMENT_RE = re.compile(
    r'\A(?P<leading>[ \t]*)'
    r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)='
    r'(?P<quote>"?)\$\([ \t]*mktemp[ \t]+'
    r'(?:-d|--directory)'
    r'(?:[ \t]+(?P<template>/[A-Za-z0-9._+,:=@%~/-]+))?'
    r'[ \t]*\)(?P=quote)'
    r'(?P<separator>[ \t]*(?:&&|;|\n)|[ \t]*\Z)',
)
QUOTED_HEREDOC_RE = re.compile(
    r"(?P<operator>(?<!<)<<(?!<)(?P<strip>-)?)[ \t]*"
    r"(?:'(?P<single>[A-Za-z0-9_][A-Za-z0-9_.-]*)'|"
    r'"(?P<double>[A-Za-z0-9_][A-Za-z0-9_.-]*)"|'
    r"\\(?P<escaped>[A-Za-z0-9_][A-Za-z0-9_.-]*))"
    r"[ \t]*$"
)
HEREDOC_LIKE_OPERATOR_RE = re.compile(
    r"(?<!<)(?P<angles><{2,})(?!<)"
)
TX_RE = re.compile(r":tx\s+(\d+)")
OP_RE = re.compile(r':op\s+"(assert|retract)"')
L_RE = re.compile(r':l\s+"((?:\\.|[^"\\])*)"')
P_RE = re.compile(r':p\s+"((?:\\.|[^"\\])*)"')
R_RE = re.compile(r':r\s+"((?:\\.|[^"\\])*)"')
FACT_PREDICATES = {
    "kind",
    "start_time",
    "end_time",
    "owner",
    "clocked_by",
    "rate",
    "linear",
    "title",
}
STORE_GIT_RE = re.compile(
    r"/nix/store/[a-z0-9]{32}-git(?:-[^/]*)?/bin/git"
)
STORE_COMMAND_FAMILIES = {
    "basename": "coreutils",
    "cat": "coreutils",
    "cut": "coreutils",
    "dirname": "coreutils",
    "head": "coreutils",
    "ls": "coreutils",
    "mkdir": "coreutils",
    "mktemp": "coreutils",
    "readlink": "coreutils",
    "realpath": "coreutils",
    "rm": "coreutils",
    "stat": "coreutils",
    "tail": "coreutils",
    "tr": "coreutils",
    "uniq": "coreutils",
    "wc": "coreutils",
    "grep": "gnugrep",
    "jq": "jq",
    "rg": "ripgrep",
    "sed": "gnused",
    "which": "which",
    "git": "git",
    "north": "north",
}
SHELL_BUILTINS = {
    "[",
    "cd",
    "echo",
    "false",
    "printf",
    "pwd",
    "test",
    "true",
    "type",
}
EXECUTION_FREE_COMMANDS = {
    "[",
    "basename",
    "cat",
    "cut",
    "dirname",
    "echo",
    "false",
    "grep",
    "head",
    "jq",
    "ls",
    "printf",
    "pwd",
    "readlink",
    "realpath",
    "stat",
    "tail",
    "test",
    "tr",
    "true",
    "type",
    "uniq",
    "wc",
    "which",
}
FS_MUTATORS = {
    "cp",
    "install",
    "ln",
    "mkdir",
    "mv",
    "rm",
    "rsync",
    "touch",
}
GIT_MUTATORS = {
    "add",
    "apply",
    "branch",
    "checkout",
    "cherry-pick",
    "clean",
    "clone",
    "commit",
    "fetch",
    "init",
    "merge",
    "mv",
    "pull",
    "push",
    "rebase",
    "reset",
    "restore",
    "rm",
    "stash",
    "switch",
    "tag",
    "worktree",
}
PACKAGE_MUTATORS = {"npm", "pnpm", "yarn", "bun"}
SHELL_PUNCTUATION = ";&|()<>\n"
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n"}
WRITE_REDIRECTS = {">", ">>", ">|", "&>", "&>>", "<>", ">&"}
READ_REDIRECTS = {"<", "<<", "<<<", "<&"}
PUNCTUATION_BOUNDARIES = {"(", ")", "\n"}
SUPPORTED_PUNCTUATION_OPERATORS = (
    (SEPARATORS - PUNCTUATION_BOUNDARIES)
    | WRITE_REDIRECTS
    | READ_REDIRECTS
)


class AdmissionUnavailable(Exception):
    """The core cannot prove a safe admission decision."""


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise AdmissionUnavailable(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def emit_json(value: dict[str, object]) -> None:
    print(json.dumps(value, separators=(",", ":")))


def deny_unavailable() -> None:
    emit_json(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "billable_clock_guard_unavailable",
            }
        }
    )


def emit_attestation(value: str) -> None:
    if os.environ.get("NORTH_CLOCK_GUARD_ATTEST") == "1":
        print(f'{{ "northClockGuard": "{value}" }}')


def client_of(path: str) -> str | None:
    match = CLIENT_RE.search(path)
    return match.group(1) if match else None


def canonical_path(path: object, cwd: str) -> str:
    if not isinstance(path, str) or not path or "\t" in path or "\n" in path:
        raise AdmissionUnavailable("invalid path")
    expanded = os.path.expanduser(path)
    if not os.path.isabs(expanded):
        expanded = os.path.join(cwd or os.getcwd(), expanded)
    return os.path.realpath(os.path.abspath(expanded))


def scan_shell_source(command: str) -> tuple[str, str, bool]:
    """Preserve quoted newlines while retaining executable shell controls.

    ``shlex`` removes quote provenance before returning tokens.  Protect only
    newlines proven to be inside ordinary single or double quotes so they
    remain argument data, and report substitutions that stay executable in
    unquoted or double-quoted text.  Backslash-newline is deliberately outside
    the supported grammar: Bash removes it before parsing, which can expose a
    command shape different from the source inspected here.
    """
    used = set(command)
    sentinel = next(
        (
            chr(codepoint)
            for codepoint in range(0xE000, 0xF900)
            if chr(codepoint) not in used
        ),
        None,
    )
    if sentinel is None:
        raise AdmissionUnavailable("quoted-newline sentinel exhausted")

    prepared: list[str] = []
    quote = ""
    active_substitution = False
    index = 0
    while index < len(command):
        character = command[index]
        following = command[index + 1] if index + 1 < len(command) else ""

        if quote == "single":
            if character == "'":
                quote = ""
            prepared.append(sentinel if character == "\n" else character)
            index += 1
            continue

        if character == "\\":
            if following == "\n" or (
                following == "\r"
                and index + 2 < len(command)
                and command[index + 2] == "\n"
            ):
                raise AdmissionUnavailable("escaped newline continuation")
            prepared.append(character)
            if following:
                prepared.append(following)
                index += 2
            else:
                index += 1
            continue

        if quote == "double":
            if character == '"':
                quote = ""
            elif character == "`" or (
                character == "$" and following == "("
            ):
                active_substitution = True
            prepared.append(sentinel if character == "\n" else character)
            index += 1
            continue

        if character == "'":
            if prepared and prepared[-1] == "$":
                raise AdmissionUnavailable("unsupported ANSI-C shell quote")
            quote = "single"
        elif character == '"':
            quote = "double"
        elif character == "`" or (
            character == "$" and following == "("
        ):
            active_substitution = True
        prepared.append(character)
        index += 1

    return "".join(prepared), sentinel, active_substitution


def command_is_exact_north_control_source(command: str) -> bool:
    """Recognize one trusted North command in linear time from shell source."""
    if os.environ.get("BASH_ENV") or os.environ.get("ENV"):
        return False
    _prepared, _quoted_newline, active_substitution = scan_shell_source(
        command
    )
    if active_substitution:
        return False

    executable: list[str] = []
    words = 0
    word_started = False
    quote = ""
    index = 0
    while index < len(command):
        character = command[index]
        following = command[index + 1] if index + 1 < len(command) else ""

        if quote == "single":
            if character == "'":
                quote = ""
            index += 1
            continue

        if character == "\\":
            if not following or words == 0:
                return False
            word_started = True
            index += 2
            continue

        if quote == "double":
            if character == '"':
                quote = ""
            index += 1
            continue

        if character in {"'", '"'}:
            if words == 0:
                return False
            quote = "single" if character == "'" else "double"
            word_started = True
            index += 1
            continue
        if character in " \t\r":
            if word_started:
                words += 1
                word_started = False
            index += 1
            continue
        if character in SHELL_PUNCTUATION:
            return False
        if words == 0:
            executable.append(character)
        word_started = True
        index += 1

    if quote:
        return False
    if word_started:
        words += 1
    token = "".join(executable)
    return (
        words >= 2
        and os.path.basename(token) == "north"
        and trusted_command_token(token)
    )


def shell_tokens(command: str) -> list[str]:
    prepared, quoted_newline, _active_substitution = scan_shell_source(command)
    try:
        lexer = shlex.shlex(
            prepared,
            posix=True,
            punctuation_chars=SHELL_PUNCTUATION,
        )
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        lexer.commenters = ""
        raw_tokens = list(lexer)
    except ValueError as error:
        raise AdmissionUnavailable("malformed shell") from error

    # shlex coalesces adjacent punctuation across newlines and parentheses.
    # Split those unambiguous boundaries, then require every residual operator
    # to be exact so executable grammar can never fall through as argv.
    result: list[str] = []
    punctuation = frozenset(SHELL_PUNCTUATION)
    for token in raw_tokens:
        if not token or any(character not in punctuation for character in token):
            if "\n" in token:
                raise AdmissionUnavailable("unsupported mixed newline token")
            result.append(token.replace(quoted_newline, "\n"))
            continue

        operator = ""
        for character in token:
            if character not in PUNCTUATION_BOUNDARIES:
                operator += character
                continue
            if operator:
                if operator not in SUPPORTED_PUNCTUATION_OPERATORS:
                    raise AdmissionUnavailable("unsupported shell punctuation")
                result.append(operator)
                operator = ""
            result.append(character)
        if operator:
            if operator not in SUPPORTED_PUNCTUATION_OPERATORS:
                raise AdmissionUnavailable("unsupported shell punctuation")
            result.append(operator)
    return result


def simple_commands(tokens: list[str]) -> Iterable[list[str]]:
    current: list[str] = []
    for token in tokens:
        if token in SEPARATORS:
            if current:
                yield current
                current = []
            continue
        current.append(token)
    if current:
        yield current


def guarded_expansions_are_double_quoted(command: str) -> bool:
    """Require every exact guarded expansion to retain Bash word integrity."""
    starts = {match.start() for match in GUARDED_EMPTY_EXPANSION_RE.finditer(command)}
    if not starts:
        return True

    quote = ""
    states: dict[int, tuple[str, bool]] = {}
    index = 0
    while index < len(command):
        character = command[index]
        states[index] = (quote, False)
        if quote == "single":
            if character == "'":
                quote = ""
            index += 1
            continue
        if character == "\\":
            if index + 1 < len(command):
                states[index + 1] = (quote, True)
                index += 2
            else:
                index += 1
            continue
        if character == '"':
            quote = "" if quote == "double" else "double"
        elif not quote and character == "'":
            quote = "single"
        index += 1

    return all(states.get(start) == ("double", False) for start in starts)


def expand_shell_word(
    word: str,
    variables: dict[str, tuple[str, bool, str | None]],
    allow_guarded_expansion: bool,
) -> tuple[str, bool, str | None]:
    ambiguous = False
    provenance_root: str | None = None
    if word == "~" or word.startswith("~/"):
        home, home_ambiguous, _home_proven = variables.get(
            "HOME", ("", False, None)
        )
        word = f"{home}{word[1:]}"
        ambiguous = home_ambiguous

    guarded = (
        GUARDED_NONCLIENT_PATH_WORD_RE.fullmatch(word)
        if allow_guarded_expansion
        else None
    )
    if guarded is not None:
        name = guarded.group("name")
        value, value_ambiguous, proven_root = variables.get(
            name, ("", True, None)
        )
        suffix = guarded.group("suffix")
        suffix_components = [component for component in suffix.split("/") if component]
        parent = os.path.realpath(os.path.dirname(value)) if value else ""
        canonical_value = os.path.realpath(value) if value else ""
        if (
            value
            and not value_ambiguous
            and proven_root is not None
            and os.path.isabs(value)
            and os.path.isdir(parent)
            and not CLIENT_NAMESPACE_RE.search(parent)
            and not CLIENT_NAMESPACE_RE.search(canonical_value)
            and not any(component in {".", ".."} for component in suffix_components)
        ):
            word = f"{guarded.group('option') or ''}{value}{suffix}"
            provenance_root = proven_root

    def replace(match: re.Match[str]) -> str:
        nonlocal ambiguous
        name = match.group(1) or match.group(2)
        value, value_ambiguous, _proven_nonclient = variables.get(
            name, ("", False, None)
        )
        ambiguous = ambiguous or value_ambiguous
        return value

    expanded = SIMPLE_VARIABLE_RE.sub(replace, word)
    if "$" in expanded or "`" in expanded:
        ambiguous = True
    return expanded, ambiguous, provenance_root


def literal_assignment_proves_nonclient_path(
    raw_value: str,
    value: str,
    uncertain: bool,
    cwd: str,
) -> bool:
    """Prove one assignment-only absolute literal without laundering input."""
    if (
        uncertain
        or raw_value != value
        or LITERAL_ABSOLUTE_PATH_RE.fullmatch(raw_value) is None
        or not os.path.isabs(value)
        or any(component in {".", ".."} for component in value.split("/") if component)
    ):
        return False
    canonical = canonical_path(value, cwd)
    if CLIENT_NAMESPACE_RE.search(canonical):
        return False
    for raw_root in LITERAL_SCRATCH_ROOTS:
        root = os.path.realpath(raw_root)
        if canonical != root and os.path.commonpath([root, canonical]) == root:
            return True
    return False


def safe_set_preamble_end(command: str) -> int:
    """Accept only a bounded ``set`` preamble that enables pipefail.

    ``-e`` and ``-u`` may be combined or separate, but no other option,
    operand, expansion, or command may precede the proved assignment.
    """
    match = SAFE_SET_PREAMBLE_RE.match(command)
    if match is None:
        return 0
    tokens = match.group("arguments").split()
    seen: set[str] = set()
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if re.fullmatch(r"-[euo]+", token) is None:
            return 0
        for offset, option in enumerate(token[1:]):
            if option in seen or (option == "o" and offset != len(token) - 2):
                return 0
            seen.add(option)
            if option == "o":
                index += 1
                if index >= len(tokens) or tokens[index] != "pipefail":
                    return 0
        index += 1
    return match.end() if "o" in seen else 0


def _normalize_safe_mktemp_assignment(
    command: str,
    cwd: str,
) -> tuple[str, tuple[str, str] | None]:
    """Replace one proved directory assignment with its non-client scope.

    A literal absolute template takes its scope from its canonical parent and
    therefore does not inherit ``TMPDIR``. Every option-bearing, relative, or
    expanded template stays outside this deliberately small proof.
    """
    preamble_end = safe_set_preamble_end(command)
    assignment_source = command[preamble_end:]
    match = SAFE_MKTEMP_ASSIGNMENT_RE.match(assignment_source)
    if (
        not match
        or match.group("name") == "TMPDIR"
        or os.environ.get("BASH_ENV")
        or os.environ.get("ENV")
        or not trusted_command("mktemp")
    ):
        return command, None
    template = match.group("template")
    if template is not None:
        if not re.search(r"X{3,}", os.path.basename(template)):
            raise AdmissionUnavailable("invalid mktemp template")
        temp_root = canonical_path(os.path.dirname(template), cwd)
        if not os.path.isdir(temp_root):
            raise AdmissionUnavailable("missing mktemp template directory")
    else:
        temp_root = canonical_path(os.environ.get("TMPDIR") or "/tmp", cwd)
    if CLIENT_NAMESPACE_RE.search(temp_root):
        raise AdmissionUnavailable("client-scoped temporary directory")
    placeholder = os.path.join(temp_root, "north-clock-guard-mktemp")
    replacement = (
        f"{command[:preamble_end]}{match.group('leading')}{match.group('name')}="
        f"{shlex.quote(placeholder)}{match.group('separator')}"
    )
    return (
        f"{replacement}{assignment_source[match.end():]}",
        (match.group("name"), placeholder),
    )


def normalize_safe_mktemp_assignment(command: str, cwd: str) -> str:
    """Return the shell source with one proved mktemp assignment normalized."""
    normalized, _provenance = _normalize_safe_mktemp_assignment(command, cwd)
    return normalized


def strip_quoted_heredoc_bodies(command: str) -> str:
    """Remove exact expansion-free heredoc bodies from static shell analysis.

    A quoted delimiter makes the body inert data. Unquoted, malformed, nested,
    and multi-heredoc lines remain unavailable because their bodies can perform
    substitutions or are too easy to attribute incorrectly. A maximal ``<<<``
    run is a Bash here-string, not a heredoc opener, so it and every following
    line remain in the executable analysis stream.
    """
    if "<<" not in command:
        return command
    lines = command.splitlines(keepends=True)
    result: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        header = line.rstrip("\r\n")
        match = QUOTED_HEREDOC_RE.search(header)
        if match is None:
            operators = HEREDOC_LIKE_OPERATOR_RE.finditer(header)
            if any(len(operator.group("angles")) != 3 for operator in operators):
                raise AdmissionUnavailable("unsupported heredoc")
            result.append(line)
            index += 1
            continue
        if HEREDOC_LIKE_OPERATOR_RE.search(header[: match.start()]):
            raise AdmissionUnavailable("multiple heredocs")
        delimiter = (
            match.group("single")
            or match.group("double")
            or match.group("escaped")
        )
        assert delimiter is not None
        line_ending = line[len(header) :]
        result.append(f"{header[: match.start()]}{line_ending}")
        index += 1
        while index < len(lines):
            candidate = lines[index].rstrip("\r\n")
            comparable = candidate.lstrip("\t") if match.group("strip") else candidate
            index += 1
            if comparable == delimiter:
                break
        else:
            raise AdmissionUnavailable("unterminated heredoc")
    return "".join(result)


def expanded_commands(
    command: str,
    cwd: str,
) -> list[tuple[list[str], list[bool]]]:
    return [
        (segment, ambiguity)
        for segment, ambiguity, _provenance in expanded_commands_with_provenance(
            command, cwd
        )
    ]


def expanded_commands_with_provenance(
    command: str,
    cwd: str,
) -> list[tuple[list[str], list[bool], list[str | None]]]:
    command, mktemp_proof = _normalize_safe_mktemp_assignment(command, cwd)
    allow_guarded_expansion = guarded_expansions_are_double_quoted(command)
    variables = {
        name: (value, False, None)
        for name, value in os.environ.items()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name)
    }
    variables["PWD"] = (cwd, False, None)
    proof_pending = mktemp_proof is not None
    assigned_names: set[str] = set()
    result: list[tuple[list[str], list[bool], list[str | None]]] = []
    for segment in simple_commands(shell_tokens(command)):
        assignment_only = bool(segment) and all(
            ASSIGNMENT_RE.fullmatch(token) is not None for token in segment
        )
        expanded: list[str] = []
        ambiguous: list[bool] = []
        provenance: list[str | None] = []
        for word in segment:
            assignment = ASSIGNMENT_RE.fullmatch(word)
            if assignment:
                name, raw_value = assignment.groups()
                value, uncertain, _value_provenance = expand_shell_word(
                    raw_value, variables, allow_guarded_expansion
                )
                mktemp_proven = bool(
                    proof_pending
                    and mktemp_proof is not None
                    and assignment_only
                    and name == mktemp_proof[0]
                    and raw_value == mktemp_proof[1]
                    and value == mktemp_proof[1]
                    and not uncertain
                )
                literal_proven = bool(
                    assignment_only
                    and name not in assigned_names
                    and literal_assignment_proves_nonclient_path(
                        raw_value, value, uncertain, cwd
                    )
                )
                proven_root = value if mktemp_proven or literal_proven else None
                if mktemp_proven:
                    proof_pending = False
                elif mktemp_proof is not None and name == mktemp_proof[0]:
                    proof_pending = False
                assigned_names.add(name)
                variables[name] = (value, uncertain, proven_root)
                expanded.append(f"{name}={value}")
                ambiguous.append(uncertain)
                provenance.append(None)
                continue
            value, uncertain, provenance_root = expand_shell_word(
                word, variables, allow_guarded_expansion
            )
            expanded.append(value)
            ambiguous.append(uncertain)
            provenance.append(provenance_root)
        result.append((expanded, ambiguous, provenance))
    return result


def command_head(tokens: list[str]) -> tuple[str, list[str]]:
    index = 0
    while index < len(tokens) and re.match(
        r"^[A-Za-z_]\w*=.*$", tokens[index], re.S
    ):
        index += 1
    while index < len(tokens) and tokens[index] in {
        "command",
        "env",
        "nice",
        "sudo",
        "timeout",
    }:
        wrapper = tokens[index]
        index += 1
        while index < len(tokens):
            token = tokens[index]
            if re.match(r"^[A-Za-z_]\w*=.*$", token, re.S):
                index += 1
                continue
            if token.startswith("-"):
                index += 1
                continue
            if wrapper == "timeout" and re.fullmatch(
                r"[0-9]+(?:\.[0-9]+)?[smhd]?", token
            ):
                index += 1
                continue
            break
    if index >= len(tokens):
        return "", []
    return os.path.basename(tokens[index]), tokens[index + 1 :]


def trusted_store_entry(command: str, executable: str) -> str | None:
    family = STORE_COMMAND_FAMILIES.get(command)
    if not family:
        return None
    candidate = os.path.abspath(executable)
    seen: set[str] = set()
    while candidate not in seen:
        seen.add(candidate)
        if re.fullmatch(
            rf"/nix/store/[a-z0-9]{{32}}-{re.escape(family)}"
            rf"(?:-[^/]*)?/bin/{re.escape(command)}",
            candidate,
        ):
            return candidate
        if not os.path.islink(candidate):
            return None
        target = os.readlink(candidate)
        candidate = os.path.normpath(
            target
            if os.path.isabs(target)
            else os.path.join(os.path.dirname(candidate), target)
        )
    return None


def imported_shell_function(command: str) -> bool:
    return any(
        key in {f"BASH_FUNC_{command}%%", f"BASH_FUNC_{command}()"}
        for key in os.environ
    )


def trusted_command(command: str) -> bool:
    if imported_shell_function(command):
        return False
    if command in SHELL_BUILTINS:
        return True
    executable = shutil.which(command)
    return bool(executable and trusted_store_entry(command, executable))


def trusted_command_token(token: str) -> bool:
    """Prove the executable named by this exact, unexpanded shell token."""
    command = os.path.basename(token)
    if token == command:
        return trusted_command(command)
    if (
        not os.path.isabs(token)
        or os.path.normpath(token) != token
        or os.path.realpath(token) != token
        or not os.access(token, os.X_OK)
    ):
        return False
    return trusted_store_entry(command, token) == token


def git_subcommand(tokens: list[str]) -> str:
    index = 1
    while index < len(tokens):
        token = tokens[index]
        if token in {
            "-C",
            "-c",
            "--git-dir",
            "--work-tree",
            "--namespace",
            "--super-prefix",
        }:
            index += 2
            continue
        if token.startswith(
            (
                "--git-dir=",
                "--work-tree=",
                "--namespace=",
                "--super-prefix=",
            )
        ) or token in {
            "--no-pager",
            "--paginate",
            "--literal-pathspecs",
            "--no-literal-pathspecs",
            "--no-replace-objects",
            "--bare",
        }:
            index += 1
            continue
        return token
    return ""


def git_effective_cwd(tokens: list[str], cwd: str) -> str:
    """Resolve Git's leading ``-C`` chain for operand attribution."""
    current = cwd
    index = 1
    while index < len(tokens):
        token = tokens[index]
        if token == "-C":
            if index + 1 >= len(tokens):
                raise AdmissionUnavailable("missing Git -C target")
            current = canonical_path(tokens[index + 1], current)
            index += 2
            continue
        if token in {
            "-c",
            "--git-dir",
            "--work-tree",
            "--namespace",
            "--super-prefix",
        }:
            index += 2
            continue
        if token.startswith(
            (
                "--git-dir=",
                "--work-tree=",
                "--namespace=",
                "--super-prefix=",
            )
        ) or token in {
            "--no-pager",
            "--paginate",
            "--literal-pathspecs",
            "--no-literal-pathspecs",
            "--no-replace-objects",
            "--bare",
        }:
            index += 1
            continue
        break
    return current


def write_redirect_targets(tokens: list[str]) -> tuple[list[str], bool]:
    targets: list[str] = []
    malformed = False
    for index, token in enumerate(tokens):
        if token not in WRITE_REDIRECTS:
            continue
        if index + 1 >= len(tokens):
            malformed = True
            continue
        target = tokens[index + 1]
        if target == "/dev/null":
            continue
        if token == ">&" and re.fullmatch(r"&?[0-9]+|-", target):
            continue
        targets.append(target)
    return targets, malformed


def segment_is_execution_free(segment: list[str]) -> bool:
    if not segment or not trusted_command_token(segment[0]):
        return False
    command = os.path.basename(segment[0])
    if command == "git":
        return False
    if command == "cd":
        return len(segment) == 2
    return command in EXECUTION_FREE_COMMANDS


def segment_is_north_control(segment: list[str]) -> bool:
    if not segment or not trusted_command_token(segment[0]):
        return False
    command, arguments = os.path.basename(segment[0]), segment[1:]
    return (
        command == "north"
        and bool(arguments)
        and not write_redirect_targets(segment)[0]
        and not write_redirect_targets(segment)[1]
    )


def command_is_execution_free(command: str) -> bool:
    if os.environ.get("BASH_ENV") or os.environ.get("ENV"):
        return False
    if command_is_exact_north_control_source(command):
        return True
    stripped = re.sub(
        r"(?:\d*>\s*&\s*\d+|\d+>\s*/dev/null|>\s*&\s*\d+)",
        "",
        command,
    )
    _prepared, _quoted_newline, active_substitution = scan_shell_source(
        stripped
    )
    if active_substitution:
        return False
    tokens = shell_tokens(stripped)
    redirect_targets, malformed_redirect = write_redirect_targets(tokens)
    if redirect_targets or malformed_redirect:
        return False
    commands = list(simple_commands(tokens))
    if len(commands) == 1 and segment_is_north_control(commands[0]):
        return True
    return bool(commands) and all(
        segment_is_execution_free(segment) for segment in commands
    )


def bounded_brace_expansion(word: str) -> list[str]:
    pending = [word]
    expanded: list[str] = []
    while pending:
        current = pending.pop()
        match = re.search(r"\{([^{}]+)\}", current)
        if not match:
            expanded.append(current)
            if len(expanded) + len(pending) > MAX_PATH_EXPANSIONS:
                raise AdmissionUnavailable("too many path expansions")
            continue
        body = match.group(1)
        alternatives = body.split(",") if "," in body else []
        range_match = re.fullmatch(
            r"(-?[0-9]+|[A-Za-z])\.\.(-?[0-9]+|[A-Za-z])",
            body,
        )
        if not alternatives and range_match:
            start, end = range_match.groups()
            if start.lstrip("-").isdigit() and end.lstrip("-").isdigit():
                first, last = int(start), int(end)
                step = 1 if first <= last else -1
                alternatives = [
                    str(value) for value in range(first, last + step, step)
                ]
            elif len(start) == 1 and len(end) == 1:
                first, last = ord(start), ord(end)
                step = 1 if first <= last else -1
                alternatives = [
                    chr(value) for value in range(first, last + step, step)
                ]
        if not alternatives:
            expanded.append(current)
            continue
        if len(alternatives) + len(expanded) + len(pending) > MAX_PATH_EXPANSIONS:
            raise AdmissionUnavailable("too many path expansions")
        prefix, suffix = current[: match.start()], current[match.end() :]
        pending.extend(f"{prefix}{value}{suffix}" for value in alternatives)
    return expanded


def path_fragments(word: str) -> Iterable[str]:
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", word):
        return
    for fragment in re.split(r"""[\s"'`();]+""", word):
        fragment = fragment.strip("[]")
        if not fragment:
            continue
        if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", fragment):
            continue
        if "=" in fragment:
            prefix, value = fragment.split("=", 1)
            if "/" not in prefix and value:
                fragment = value
        if "/" not in fragment and not fragment.startswith("~"):
            continue
        embedded_absolute = fragment.find("/")
        if (
            embedded_absolute > 0
            and not fragment.startswith(("./", "../"))
            and ":" in fragment[:embedded_absolute]
        ):
            fragment = fragment[embedded_absolute:]
        yield fragment


def static_pattern_prefix(pattern: str) -> str:
    components = pattern.split(os.sep)
    stable: list[str] = []
    for component in components:
        if any(marker in component for marker in ("*", "?", "[", "{")):
            break
        stable.append(component)
    if len(stable) == len(components):
        return pattern
    prefix = os.sep.join(stable)
    return prefix or os.sep


def resolve_path_candidates(
    raw: str,
    cwd: str,
    *,
    expand_globs: bool = True,
) -> list[str]:
    """Resolve paths, optionally enumerating matches for known mutators.

    Generic commands canonicalize the pattern itself. That still resolves a
    direct symlink prefix and exposes literal/wildcard client roots, without
    walking an arbitrarily large wholly-nonclient glob.
    """
    resolved: list[str] = []
    raw_candidates = (
        bounded_brace_expansion(raw)
        if expand_globs
        else [raw]
    )
    for raw_candidate in raw_candidates:
        for candidate in path_fragments(raw_candidate):
            expanded = os.path.expanduser(candidate)
            pattern = (
                expanded
                if os.path.isabs(expanded)
                else os.path.join(cwd or os.getcwd(), expanded)
            )
            if not expand_globs:
                generic_candidates = [pattern]
                prefix = static_pattern_prefix(pattern)
                if prefix != pattern:
                    generic_candidates.append(prefix)
                for generic_candidate in generic_candidates:
                    canonical = canonical_path(generic_candidate, cwd)
                    if canonical not in resolved:
                        resolved.append(canonical)
                continue
            matches = glob(pattern, recursive=False)
            selected = matches or [pattern]
            if len(resolved) + len(selected) > MAX_PATH_EXPANSIONS:
                raise AdmissionUnavailable("too many path expansions")
            for matched in selected:
                resolved.append(canonical_path(matched, cwd))
    return resolved


def add_candidate(
    result: dict[str, list[str]],
    raw: str,
    cwd: str,
    *,
    expand_globs: bool = True,
) -> None:
    if raw in {"", ".", "..", "&"} or re.match(
        r"^[A-Za-z][A-Za-z0-9+.-]*://", raw
    ):
        return
    if raw.startswith("-") and "=" not in raw:
        return
    for canonical in resolve_path_candidates(
        raw,
        cwd,
        expand_globs=expand_globs,
    ):
        client = client_of(canonical)
        if CLIENT_ROOT in canonical and not client:
            raise AdmissionUnavailable("ambiguous client path")
        if client:
            result.setdefault(client, []).append(canonical)


def mutation_paths(command: str, cwd: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    commands = expanded_commands(command, cwd)

    for segment, ambiguity in commands:
        for index, token in enumerate(segment):
            if token not in WRITE_REDIRECTS:
                continue
            if index + 1 >= len(segment):
                continue
            target = segment[index + 1]
            if (
                token == ">&"
                and re.fullmatch(r"&?[0-9]+|-", target)
            ) or target == "/dev/null":
                continue
            if ambiguity[index + 1]:
                raise AdmissionUnavailable("ambiguous redirect target")
            add_candidate(result, target, cwd)

        command_name, arguments = command_head(segment)
        if not command_name:
            continue
        argument_offset = len(segment) - len(arguments)
        argument_ambiguity = ambiguity[argument_offset:]
        candidates: list[tuple[str, bool]] = []
        candidate_cwd = cwd
        if command_name in FS_MUTATORS:
            candidates = [
                (argument, uncertain)
                for argument, uncertain in zip(
                    arguments, argument_ambiguity, strict=True
                )
                if not argument.startswith("-")
            ]
        elif command_name == "tee":
            candidates = [
                (argument, uncertain)
                for argument, uncertain in zip(
                    arguments, argument_ambiguity, strict=True
                )
                if not argument.startswith("-")
            ]
        elif command_name in {"sed", "perl"} and any(
            argument == "--in-place"
            or re.fullmatch(r"-[^-]*i[^-]*", argument)
            for argument in arguments
        ):
            candidates = [
                (argument, uncertain)
                for argument, uncertain in zip(
                    arguments, argument_ambiguity, strict=True
                )
                if not argument.startswith("-")
            ]
        elif command_name == "dd":
            candidates = [
                (argument, uncertain)
                for argument, uncertain in zip(
                    arguments, argument_ambiguity, strict=True
                )
                if argument.startswith("of=")
            ]
        elif command_name in PACKAGE_MUTATORS and any(
            argument in {"add", "install", "run"} for argument in arguments
        ):
            candidates = list(
                zip(arguments, argument_ambiguity, strict=True)
            )
        elif command_name == "git":
            full = ["git", *arguments]
            if git_subcommand(full) in GIT_MUTATORS:
                candidate_cwd = git_effective_cwd(full, cwd)
                candidates = list(
                    zip(arguments, argument_ambiguity, strict=True)
                )
        for candidate, uncertain in candidates:
            if uncertain:
                raise AdmissionUnavailable("ambiguous mutator operand")
            add_candidate(result, candidate, candidate_cwd)
    return result


def git_scope_paths(command: str, cwd: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for segment, ambiguity in expanded_commands(command, cwd):
        command_name, arguments = command_head(segment)
        if command_name != "git":
            continue
        argument_offset = len(segment) - len(arguments)
        argument_ambiguity = ambiguity[argument_offset:]
        for index, argument in enumerate(arguments):
            if index > 0 and arguments[index - 1] in {
                "-C",
                "--git-dir",
                "--work-tree",
            }:
                if argument_ambiguity[index]:
                    raise AdmissionUnavailable("ambiguous Git scope")
                add_candidate(result, argument, cwd)
            elif argument.startswith(("--git-dir=", "--work-tree=")):
                if argument_ambiguity[index]:
                    raise AdmissionUnavailable("ambiguous Git scope")
                add_candidate(result, argument.split("=", 1)[1], cwd)
    return result


def generic_command_paths(
    command: str,
    cwd: str,
) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for segment, ambiguity in expanded_commands(command, cwd):
        if (
            segment_is_execution_free(segment)
            or segment_is_north_control(segment)
        ):
            continue
        command_name, arguments = command_head(segment)
        if not command_name:
            continue
        segment_cwd = (
            git_effective_cwd(["git", *arguments], cwd)
            if command_name == "git"
            else cwd
        )
        for index, (word, uncertain) in enumerate(
            zip(segment, ambiguity, strict=True)
        ):
            if word in WRITE_REDIRECTS:
                continue
            if uncertain and CLIENT_ROOT in word:
                raise AdmissionUnavailable("ambiguous client operand")
            add_candidate(result, word, segment_cwd, expand_globs=False)
    return result


def segment_is_bounded_nonclient_command(segment: list[str]) -> bool:
    if not segment or not trusted_command_token(segment[0]):
        return False
    command, arguments = os.path.basename(segment[0]), segment[1:]
    if not command or command == "cd":
        return False
    if segment_is_execution_free(segment):
        return True
    if command == "git":
        return git_subcommand([command, *arguments]) in (
            GIT_MUTATORS | {"log", "status"}
        ) and not any(
            token in {"-C", "-c", "--git-dir", "--work-tree"}
            or token.startswith(
                (
                    "--git-dir=",
                    "--work-tree=",
                    "--namespace=",
                    "--super-prefix=",
                )
            )
            for token in arguments
        )
    if command == "sed":
        return (
            len(arguments) >= 3
            and arguments[0] == "-n"
            and bool(
                re.fullmatch(
                    r"(?:[0-9]+|\$)(?:,(?:[0-9]+|\$))?p",
                    arguments[1],
                )
            )
            and all(not argument.startswith("-") for argument in arguments[2:])
        )
    if command == "rg":
        return (
            not os.environ.get("RIPGREP_CONFIG_PATH")
            and not any(
                argument == "--pre"
                or argument.startswith(("--pre=", "--pre-glob"))
                for argument in arguments
            )
        )
    return False


def leading_nonclient_scope_target(command: str, cwd: str) -> str | None:
    """Prove a static `cd /nonclient && ...` scope for a bounded chain."""
    if (
        os.environ.get("BASH_ENV")
        or os.environ.get("ENV")
        or "`" in command
        or "$(" in command
        or "\n" in command
    ):
        return None
    tokens = shell_tokens(command)
    separators = [token for token in tokens if token in SEPARATORS]
    segments = list(simple_commands(tokens))
    if (
        len(segments) < 2
        or len(separators) != len(segments) - 1
        or any(separator != "&&" for separator in separators)
    ):
        return None
    index = 0
    while index < len(segments) and not command_head(segments[index])[0]:
        index += 1
    if index >= len(segments):
        return None
    if (
        segments[index][0] != "cd"
        or len(segments[index]) != 2
        or not trusted_command_token(segments[index][0])
    ):
        return None
    arguments = segments[index][1:]
    raw_target = arguments[0]
    if not raw_target.startswith(("/", "~")):
        return None
    target = canonical_path(raw_target, cwd)
    if CLIENT_NAMESPACE_RE.search(target):
        return None
    remainder = segments[index + 1 :]
    if not remainder or not all(
        segment_is_bounded_nonclient_command(segment)
        for segment in remainder
    ):
        return None
    return target


def explicit_nonclient_git_target(command: str, cwd: str) -> str | None:
    """Return the exact absolute non-client scope of a single `git -C` call."""
    if os.environ.get("BASH_ENV") or os.environ.get("ENV"):
        return None
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return None
    if (
        len(tokens) < 4
        or tokens[0] != "git"
        or tokens[1] != "-C"
        or not tokens[2].startswith(("/", "~"))
        or not trusted_command("git")
        or any(
            token in {"-c", "--git-dir", "--work-tree"}
            or token.startswith(("--git-dir=", "--work-tree="))
            for token in tokens[3:]
        )
        or any(marker in command for marker in (";", "&", "|", "`", "$(", "\n"))
    ):
        return None
    target = canonical_path(tokens[2], cwd)
    return None if client_of(target) else target


def explicit_nonclient_redirects(
    segment: list[str],
    ambiguity: list[bool],
    cwd: str,
) -> tuple[bool, bool]:
    """Return (has-write-redirect, all-write-redirects-proved-nonclient)."""
    has_redirect = False
    for index, token in enumerate(segment):
        if token not in WRITE_REDIRECTS:
            continue
        if index + 1 >= len(segment):
            return True, False
        target = segment[index + 1]
        if (
            token == ">&" and re.fullmatch(r"&?[0-9]+|-", target)
        ) or target == "/dev/null":
            continue
        has_redirect = True
        if ambiguity[index + 1] or not target.startswith(("/", "~")):
            return True, False
        resolved = canonical_path(target, cwd)
        if CLIENT_NAMESPACE_RE.search(resolved):
            return True, False
    return has_redirect, True


def git_segment_has_explicit_nonclient_scope(
    segment: list[str],
    ambiguity: list[bool],
    cwd: str,
) -> bool:
    if (
        len(segment) < 4
        or segment[0] != "git"
        or segment[1] != "-C"
        or ambiguity[2]
        or not segment[2].startswith(("/", "~"))
        or not trusted_command_token(segment[0])
    ):
        return False
    target = canonical_path(segment[2], cwd)
    if CLIENT_NAMESPACE_RE.search(target):
        return False
    arguments = segment[3:]
    if any(ambiguity[3:]):
        return False
    if any(
        token in {"-C", "-c", "--git-dir", "--work-tree"}
        or token.startswith(
            (
                "--git-dir=",
                "--work-tree=",
                "--namespace=",
                "--super-prefix=",
            )
        )
        for token in arguments
    ):
        return False
    subcommand = git_subcommand(["git", *arguments])
    return subcommand in (GIT_MUTATORS | {"log", "status"})


def filesystem_segment_has_explicit_nonclient_operands(
    segment: list[str],
    ambiguity: list[bool],
    provenance: list[str | None],
    cwd: str,
) -> bool:
    if not segment or not trusted_command_token(segment[0]):
        return False
    command = os.path.basename(segment[0])
    allowed_options = {
        "mkdir": {"-p", "--parents", "--"},
        "rm": {"-f", "-r", "-R", "-fr", "-rf", "--force", "--recursive", "--"},
    }
    if command not in allowed_options or any(
        token in WRITE_REDIRECTS for token in segment
    ):
        return False

    operands: list[tuple[str, bool, str | None]] = []
    options_done = False
    for index, argument in enumerate(segment[1:], start=1):
        if not options_done and argument.startswith("-"):
            if argument not in allowed_options[command]:
                return False
            options_done = options_done or argument == "--"
            continue
        operands.append((argument, ambiguity[index], provenance[index]))
    if not operands:
        return False

    for argument, uncertain, provenance_root in operands:
        if uncertain or provenance_root is None or not os.path.isabs(argument):
            return False
        root = canonical_path(provenance_root, cwd)
        target = canonical_path(argument, cwd)
        if (
            CLIENT_NAMESPACE_RE.search(root)
            or CLIENT_NAMESPACE_RE.search(target)
            or os.path.commonpath([root, target]) != root
        ):
            return False
    return True


def command_has_bounded_explicit_nonclient_effects(
    command: str,
    cwd: str,
) -> bool:
    """Prove every effect in a bounded compound shell chain is non-client.

    This is deliberately narrower than general shell interpretation. It covers
    the coordinator's isolated-workspace lifecycle: trusted Git calls with an
    exact non-client ``-C``, guarded-root ``mkdir``/``rm`` operands, and inert
    data writers whose output redirects are exact non-client paths.
    """
    normalized_command = normalize_safe_mktemp_assignment(command, cwd)
    if os.environ.get("BASH_ENV") or os.environ.get("ENV"):
        return False
    if "`" in normalized_command or "$(" in normalized_command:
        return False
    tokens = shell_tokens(normalized_command)
    if any(
        token in {"||", "|", "&", "(", ")"}
        for token in tokens
        if token in SEPARATORS
    ):
        return False
    proved_effect = False
    for segment, ambiguity, provenance in expanded_commands_with_provenance(
        command, cwd
    ):
        command_name, _arguments = command_head(segment)
        if not command_name:
            if any(ambiguity):
                return False
            continue
        has_redirect, redirects_safe = explicit_nonclient_redirects(
            segment, ambiguity, cwd
        )
        if not redirects_safe:
            return False
        if segment_is_execution_free(segment) and not has_redirect:
            continue
        direct_command = os.path.basename(segment[0]) if segment else ""
        if (
            direct_command in {"cat", "echo", "printf"}
            and trusted_command_token(segment[0])
            and has_redirect
        ):
            proved_effect = True
            continue
        if git_segment_has_explicit_nonclient_scope(segment, ambiguity, cwd):
            proved_effect = True
            continue
        if filesystem_segment_has_explicit_nonclient_operands(
            segment, ambiguity, provenance, cwd
        ):
            proved_effect = True
            continue
        return False
    return proved_effect


def classify_edit(tool_input: dict[str, object], cwd: str) -> tuple[str, str] | None:
    path = canonical_path(tool_input.get("file_path"), cwd)
    client = client_of(path)
    return (client, os.path.dirname(path)) if client else None


def find_patch(value: object) -> str | None:
    if isinstance(value, str):
        return value if "*** Begin Patch" in value else None
    if isinstance(value, dict):
        for child in value.values():
            found = find_patch(child)
            if found is not None:
                return found
    return None


def classify_patch(tool_input: object, cwd: str) -> tuple[str, str] | None:
    patch = find_patch(tool_input)
    if not isinstance(patch, str) or not patch:
        raise AdmissionUnavailable("missing patch")
    explicit: list[str] = []
    patch_cwd = cwd
    if isinstance(tool_input, dict):
        explicit = [
            value
            for key in ("file_path", "path")
            if isinstance((value := tool_input.get(key)), str)
        ]
        selected_cwd = tool_input.get("workdir") or tool_input.get("cwd")
        if selected_cwd is not None:
            if not isinstance(selected_cwd, str):
                raise AdmissionUnavailable("invalid patch cwd")
            patch_cwd = selected_cwd
    targets = explicit
    targets += re.findall(
        r"^\*\*\* (?:Add|Update|Delete) File:\s+(.+?)\s*$",
        patch,
        re.M,
    )
    targets += re.findall(r"^\*\*\* Move to:\s+(.+?)\s*$", patch, re.M)
    if not targets:
        raise AdmissionUnavailable("missing patch targets")
    canonical = [canonical_path(path, patch_cwd) for path in targets]
    clients = {client_of(path) for path in canonical if client_of(path)}
    if not clients:
        return None
    if len(clients) != 1:
        raise AdmissionUnavailable("multiple clients")
    client = clients.pop()
    assert client is not None
    client_targets = [
        path for path in canonical if client_of(path) == client
    ]
    common = os.path.commonpath(
        [os.path.dirname(path) for path in client_targets]
    )
    return client, common


def classify_shell(tool_input: dict[str, object], cwd: str) -> tuple[str, str] | None:
    command = tool_input.get("command", tool_input.get("cmd"))
    input_cwd = tool_input.get("workdir") or tool_input.get("cwd", "")
    if (
        not isinstance(command, str)
        or not command
        or not isinstance(input_cwd, str)
        or "\n" in input_cwd
        or "\t" in input_cwd
    ):
        raise AdmissionUnavailable("invalid shell envelope")
    shell_cwd = canonical_path(input_cwd or cwd or os.getcwd(), os.getcwd())
    if command_is_exact_north_control_source(command):
        return None
    command = strip_quoted_heredoc_bodies(command)
    leading_scope = leading_nonclient_scope_target(command, shell_cwd)
    analysis_cwd = leading_scope or shell_cwd

    paths = mutation_paths(command, analysis_cwd)
    for discovered in (
        git_scope_paths(command, analysis_cwd),
        generic_command_paths(command, analysis_cwd),
    ):
        for client, values in discovered.items():
            paths.setdefault(client, []).extend(values)
    if len(paths) > 1:
        raise AdmissionUnavailable("multiple clients")
    command_client = next(iter(paths), None)

    escape = (
        leading_scope is not None
        or explicit_nonclient_git_target(command, shell_cwd) is not None
        or command_has_bounded_explicit_nonclient_effects(command, shell_cwd)
    )
    if not escape and not re.search(r"[;&|`]|\$\(", command):
        commands = expanded_commands(command, shell_cwd)
        if len(commands) == 1:
            segment, ambiguity = commands[0]
            command_name, arguments = command_head(segment)
            argument_offset = len(segment) - len(arguments)
            argument_ambiguity = ambiguity[argument_offset:]
            if command_name in {"rm", "mv", "cp", "touch", "mkdir", "ln"}:
                operands = [
                    (argument, uncertain)
                    for argument, uncertain in zip(
                        arguments, argument_ambiguity, strict=True
                    )
                    if not argument.startswith("-")
                ]
                if any(uncertain for _argument, uncertain in operands):
                    raise AdmissionUnavailable("ambiguous filesystem operands")
                resolved_operands = [
                    resolved
                    for argument, _uncertain in operands
                    for resolved in resolve_path_candidates(
                        argument, shell_cwd
                    )
                ]
                escape = (
                    bool(operands)
                    and len(resolved_operands) >= len(operands)
                    and all(
                        argument.startswith(("/", "~"))
                        for argument, _uncertain in operands
                    )
                    and all(
                        not client_of(resolved)
                        for resolved in resolved_operands
                    )
                    and not write_redirect_targets(segment)[0]
                    and not write_redirect_targets(segment)[1]
                )

    client = (
        command_client
        if escape
        else command_client or client_of(shell_cwd)
    )
    if not client or command_is_execution_free(command):
        return None
    attribution = list(paths.get(client, []))
    if not escape and client_of(shell_cwd) == client:
        attribution.append(shell_cwd)
    if not attribution:
        raise AdmissionUnavailable("missing attribution path")
    return client, os.path.commonpath(attribution)


def classify(payload: object) -> tuple[str, str] | None:
    if not isinstance(payload, dict):
        raise AdmissionUnavailable("invalid root")
    raw_tool = payload.get("tool_name")
    if not isinstance(raw_tool, str):
        raise AdmissionUnavailable("missing tool")
    tool_name = raw_tool.rsplit(".", 1)[-1]
    tool_input = payload.get("tool_input")
    cwd = payload.get("cwd", "")
    if not isinstance(cwd, str):
        raise AdmissionUnavailable("invalid cwd")
    if tool_name in {"Edit", "Write", "MultiEdit"}:
        if not isinstance(tool_input, dict):
            raise AdmissionUnavailable("invalid edit envelope")
        return classify_edit(tool_input, cwd)
    if raw_tool.endswith("apply_patch"):
        return classify_patch(tool_input, cwd)
    if (
        tool_name in {"Bash", "shell", "exec_command"}
        or raw_tool.endswith("exec_command")
    ):
        if not isinstance(tool_input, dict):
            raise AdmissionUnavailable("invalid shell envelope")
        return classify_shell(tool_input, cwd)
    raise AdmissionUnavailable("unsupported tool")


def resolve_trusted_git() -> str:
    override = os.environ.get("NORTH_CLOCK_GUARD_GIT", "")
    user = os.environ.get("USER", "")
    home = os.environ.get("HOME", "")
    candidates = (
        [override]
        if override
        else [
            "/run/current-system/sw/bin/git",
            f"/etc/profiles/per-user/{user}/bin/git" if user else "",
            os.path.join(home, ".nix-profile/bin/git") if home else "",
            shutil.which("git") or "",
        ]
    )
    for candidate in candidates:
        if not candidate:
            continue
        resolved = os.path.realpath(candidate)
        if os.access(resolved, os.X_OK) and STORE_GIT_RE.fullmatch(resolved):
            return resolved
    raise AdmissionUnavailable("untrusted Git")


def resolve_logs() -> list[str]:
    fram_log = os.environ.get("FRAM_LOG", "")
    telemetry_log = os.environ.get("FRAM_TELEMETRY_LOG", "")
    home = os.environ.get("HOME", "")
    logs: list[str] = []
    if fram_log:
        logs.append(fram_log)
        if telemetry_log:
            logs.append(telemetry_log)
        elif fram_log.endswith("/coordination.log"):
            logs.append(f"{fram_log[:-len('/coordination.log')]}/telemetry.log")
    elif telemetry_log:
        raise AdmissionUnavailable("orphan telemetry corpus")
    elif not home:
        raise AdmissionUnavailable("missing home")
    else:
        coordination = os.path.join(
            home, ".local/state/north/coordination.log"
        )
        telemetry = os.path.join(
            home, ".local/state/north/telemetry.log"
        )
        legacy = os.path.join(home, ".local/state/north/facts.log")
        if os.path.exists(coordination) or os.path.exists(telemetry):
            logs.extend((coordination, telemetry))
        elif os.path.exists(legacy):
            logs.append(legacy)
    if not logs or any(
        not os.path.isfile(path) or not os.access(path, os.R_OK)
        for path in logs
    ):
        raise AdmissionUnavailable("unreadable corpus")
    return logs


def derive_ticket(
    client: str, target_dir: str, git: str
) -> tuple[str, str] | None:
    probe = os.path.realpath(target_dir)
    while not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            return None
        probe = parent
    git_env = {
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_ATTR_NOSYSTEM": "1",
        "HOME": "/nonexistent",
        "LC_ALL": "C",
        "PATH": os.path.dirname(git),
    }

    def git_read(*arguments: str) -> str | None:
        result = subprocess.run(
            [
                git,
                "--no-pager",
                "--no-optional-locks",
                "-C",
                probe,
                *arguments,
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=git_env,
            timeout=1,
            check=False,
            text=True,
        )
        return result.stdout.strip() if result.returncode == 0 else None

    repository = git_read("rev-parse", "--show-toplevel")
    if not repository:
        return None
    probe = os.path.realpath(repository)
    branch = git_read("symbolic-ref", "--quiet", "--short", "HEAD")
    if not branch:
        return None
    matches = re.findall(
        rf"(?i)(?<![A-Za-z0-9]){re.escape(client)}-([0-9]+)"
        rf"(?![A-Za-z0-9])",
        branch,
    )
    if len(matches) != 1:
        return None
    return f"{client.upper()}-{matches[0]}", probe


def fold_facts(logs: list[str]) -> dict[tuple[str, str], tuple[str, int]]:
    # The optional live benchmark in north-clock-guard.test.sh sets an
    # operational review threshold at 48 MiB and guards this direct fold at a
    # 1s p95 / 2s max budget. Replace it with an indexed coordinator query
    # before either threshold is reached; the Codex adapter's 3s child deadline
    # is an outer safety net, not a target.
    events: list[tuple[int, int, str, str, str, str]] = []
    for source_index, path in enumerate(logs):
        # Transaction ids are ordered within one append log, not globally
        # unique across the coordination/telemetry corpus.  Keep the source in
        # the event order so equal ids retain the configured log order used by
        # North's stable merge replay.
        seen_transactions: set[int] = set()
        with open(path, encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                predicate_match = P_RE.search(line)
                if not predicate_match:
                    raise AdmissionUnavailable(
                        f"{path}:{line_number}: missing predicate"
                    )
                predicate = predicate_match.group(1)
                if predicate not in FACT_PREDICATES:
                    continue
                matches = (
                    TX_RE.search(line),
                    OP_RE.search(line),
                    L_RE.search(line),
                    R_RE.search(line),
                )
                if not all(matches):
                    raise AdmissionUnavailable(
                        f"{path}:{line_number}: malformed relevant fact"
                    )
                transaction_match, operation_match, subject_match, object_match = matches
                assert transaction_match is not None
                assert operation_match is not None
                assert subject_match is not None
                assert object_match is not None
                transaction = int(transaction_match.group(1))
                if transaction in seen_transactions:
                    raise AdmissionUnavailable(
                        f"duplicate relevant transaction {transaction}"
                    )
                seen_transactions.add(transaction)
                events.append(
                    (
                        transaction,
                        source_index,
                        subject_match.group(1),
                        predicate,
                        operation_match.group(1),
                        object_match.group(1),
                    )
                )
    state: dict[tuple[str, str], tuple[str, int]] = {}
    for transaction, _source, subject, predicate, operation, value in sorted(events):
        key = (subject, predicate)
        if operation == "assert":
            state[key] = (value, transaction)
        elif operation == "retract" and state.get(key, (None,))[0] == value:
            state.pop(key, None)
    return state


def clock_decision(
    client: str,
    ticket: str,
    state: dict[tuple[str, str], tuple[str, int]],
) -> tuple[str, str, str]:
    by_subject: dict[str, dict[str, str]] = {}
    for (subject, predicate), (value, _transaction) in state.items():
        by_subject.setdefault(subject, {})[predicate] = value
    candidate_threads = {
        subject
        for subject, facts in by_subject.items()
        if facts.get("owner") == client
        and facts.get("linear") == ticket
        and isinstance(facts.get("title"), str)
        and bool(facts["title"].strip())
    }
    if len(candidate_threads) > 1:
        raise AdmissionUnavailable("duplicate ticket thread identity")
    exact_thread = next(iter(candidate_threads), None)
    if exact_thread is None:
        return "NOTHREAD", "", ""

    open_sessions: list[tuple[str, str]] = []
    for subject, facts in by_subject.items():
        if (
            facts.get("kind") != "client_session"
            or facts.get("clocked_by") != "user"
            or "start_time" not in facts
            or "end_time" in facts
        ):
            continue
        owner = facts.get("owner")
        rate = facts.get("rate")
        if not owner or not rate:
            raise AdmissionUnavailable("incomplete human client session")
        open_sessions.append((subject, owner))
    if len(open_sessions) > 1:
        raise AdmissionUnavailable("multiple open human client sessions")
    if not open_sessions:
        return "NOCLOCK", exact_thread, ""
    session, owner = open_sessions[0]
    if owner == client:
        return "ALLOW", exact_thread, ""
    details = " ; ".join(
        f"{session_id} owner={session_owner} clocked_by=user"
        for session_id, session_owner in open_sessions
    )
    return "MISMATCH", exact_thread, details


def denial_reason(
    kind: str,
    client: str,
    ticket: str,
    thread_id: str,
    details: str,
) -> str:
    if kind == "NOTICKET":
        return (
            "Billable client edit blocked — branch ticket is missing or "
            f"ambiguous. The client '{client}' path must be in a Git worktree "
            f"whose current branch contains exactly one {client.upper()}-NNN "
            "ticket.\nCreate or switch to the ticket branch, then retry. "
            "North coordination and clock commands remain available while "
            "this guard is denying the edit.\nDeliberate bypass: north config guards off "
            "(persistent, live) — or a session launched with "
            "AGENT_NO_AUTHORING_HOOKS=1."
        )
    if kind == "NOTHREAD":
        return (
            f"Billable client edit blocked — branch ticket '{ticket}' has no "
            "exact North traceability thread carrying both "
            f"owner='{client}' and linear='{ticket}'. Create or repair that "
            "thread; the human client clock is intentionally independent of "
            "ticket changes.\nDeliberate bypass: north config guards off "
            "(persistent, live) — or a session launched with "
            "AGENT_NO_AUTHORING_HOOKS=1."
        )
    hint = f"north clock in {client}"
    if kind == "MISMATCH":
        return (
            f"Billable client edit blocked — WRONG client clock. Ticket "
            f"'{ticket}' is traceable, but the one open human client session "
            f"does not belong to owner='{client}':\n  {details}\nClock out of "
            "the other client and into this client, then retry:\n"
            f"  north clock out\n  {hint}\nDeliberate bypass: north config "
            "guards off (persistent, live) — or a session launched with "
            "AGENT_NO_AUTHORING_HOOKS=1."
        )
    return (
        f"Billable client edit blocked — no north clock running for human "
        f"client owner '{client}' (ticket '{ticket}' is traceable). Client work is never "
        "done untracked (this gate exists because ~22h of MSA work once "
        "shipped with zero logged time and had to be reconstructed for an "
        f"invoice). Clock into the client once, then retry the edit:\n"
        f"  {hint}\nDeliberate bypass: north config guards off (persistent, "
        "live) — or a session launched with AGENT_NO_AUTHORING_HOOKS=1."
    )


def main() -> None:
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if not raw or len(raw) > MAX_INPUT_BYTES or b"\0" in raw:
        raise AdmissionUnavailable("invalid input")
    payload = json.loads(raw, object_pairs_hook=unique_object)
    classification = classify(payload)
    if classification is None:
        emit_attestation("not-applicable")
        return
    client, target_dir = classification
    git = resolve_trusted_git()
    ticket_identity = derive_ticket(client, target_dir, git)
    if ticket_identity is None:
        reason = denial_reason("NOTICKET", client, "", "", "")
        emit_json(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
        return
    ticket, _repository = ticket_identity
    state = fold_facts(resolve_logs())
    kind, thread_id, details = clock_decision(client, ticket, state)
    if kind == "ALLOW":
        emit_attestation("allow")
        return
    reason = denial_reason(kind, client, ticket, thread_id, details)
    emit_json(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }
    )


if __name__ == "__main__":
    try:
        main()
    except Exception:
        deny_unavailable()
