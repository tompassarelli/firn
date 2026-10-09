#!/usr/bin/env python3
"""Decide whether one tool call writes into a protected checkout.

TWO PROTECTED SHAPES, TWO REMEDIES

A `main/` checkout is protected because it is the clean product and any dirt in
it is the human's; the remedy is a lane under `<container>/worktrees/`. A
`pins/<full-object-id>/` checkout is protected because something OUTSIDE the repository
consumes that immutable commit at that exact path. The remedy is a new
hash-named pin plus a consumer update, never mutation of the existing checkout.
`protected_project` returns the kind so both nouns and both remedies stay
correct at every deny site.

BASH COVERAGE

`tool_input.file_path` exists only for Edit/Write/MultiEdit. A Bash call
carries `tool_input.command` instead, so this module parses Bash commands
(git verbs, redirects, in-place/destination-taking commands, interpreter
heredocs) to catch writes that route through the shell rather than a
file_path.

APPLY_PATCH

apply_patch carries Add/Update/Delete File targets and Move to destinations
inside its patch envelope. Both direct tool calls and Bash string/argv entrances
are parsed.

READ vs WRITE

Reads from a primary stay allowed — `git log`, `git status`, `grep`, `cat`. So
does the sanctioned escape route the deny message itself recommends:
`git worktree add` (into `<container>/worktrees/`) and
`git fetch LANE BRANCH:refs/heads/main`. Pin contents and HEAD have no sanctioned
mutation: a new full-object-ID pin is created when a consumer advances.

WIP DESTRUCTION

A separate, louder class: `reset --hard`, `stash`, `checkout -- <path>`,
`restore`, `clean -f` against a main checkout throw away uncommitted work that
is the human's, not the lane's. It is checked across EVERY git call in the
command, so a sanctioned verb earlier in the line cannot shield it.

SANCTIONED TOOLS

`wt-rescue` is the remediation this guard's deny message recommends, and it
performs internally the very operations denied raw. Its own command segment is
excised before any rule runs; every other segment on the line is still scanned.

FAIL-OPEN for unparseable commands, unknown shapes, and internal exceptions. A
recognized apply_patch call whose envelope cannot be parsed is denied: it is a
write, and a write whose targets cannot be read cannot be checked.
"""

import json
import os
import re
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from launch_critical_paths import (  # noqa: E402
    MAIN_KIND, code_root, hit_advice, hit_noun, is_pin, pin_sidecar, protected_project,
    repository_container_spill, worktree_advice)

# git subcommands that change the repository or working tree.
MUTATING_GIT = {
    "commit", "add", "reset", "checkout", "switch", "restore", "merge",
    "rebase", "cherry-pick", "revert", "stash", "apply", "am", "push",
    "clean", "rm", "mv", "gc", "prune", "filter-branch", "update-ref",
}

# Explicitly allowed from a primary — this is one way work LANDS in it.
# `git worktree` is handled by subcommand below because add/prune are compliant,
# while remove/move may target an immutable pin.
SANCTIONED_GIT = {"fetch"}

# merge/pull are mutations, but --ff-only cannot dirty the tree or invent a
# commit: it either fast-forwards or refuses. `git fetch LANE BRANCH:refs/heads/main`
# — the other landing form — FAILS when main is checked out, which it always is
# under this layout, so without these there is no way to land at all.
FF_ONLY_GIT = {"merge", "pull"}

# Commands whose job is to modify a file in place.
WRITE_COMMANDS = {
    "tee", "truncate", "install", "patch", "dd", "shred",
}

# Commands that write to a destination argument (checked positionally).
COPY_COMMANDS = {"cp", "mv", "rsync", "ln"}

DESTRUCTIVE_COMMANDS = {"rm", "rmdir", "shred", "unlink"}

# Commands that never execute or write their arguments: in `grep -n install
# f`, `install` is a pattern. Their redirects are still checked.
READ_ONLY_COMMANDS = {
    "grep", "egrep", "fgrep", "rg", "cat", "head", "tail", "less", "more",
    "wc", "ls", "echo", "printf", "file", "stat", "diff", "cmp", "cut", "tr",
    "jq", "nl", "basename", "dirname", "realpath", "readlink", "du", "which",
    "type", "man", "test", "[",
}

INTERPRETERS = {"python", "python3", "perl", "ruby", "node", "bb", "bash", "sh", "zsh"}

# `git stash` subcommands that only report.
STASH_READS = {"list", "show"}

# Tools whose whole job is a sanctioned remediation of a protected checkout.
# Denying one leaves the deny message recommending a move the guard forbids.
SANCTIONED_TOOLS = {"wt-rescue"}

# `bun install` is not install(1). A package manager's subcommand collides with
# a real write command's name, and its arguments are package names, not paths.
PACKAGE_MANAGERS = {
    "bun", "bunx", "npm", "npx", "pnpm", "pnpx", "yarn", "deno",
    "cargo", "pip", "pip3", "uv", "poetry", "gem", "go", "nix",
}

# Header forms are the complete grammar the Codex binary accepts:
# Add File / Update File / Delete File, plus Move to inside an update hunk.
PATCH_BEGIN = "*** Begin Patch"
PATCH_FILE_HEADER = re.compile(r"^\*\*\* (?:Add|Update|Delete) File:\s+(.+?)\s*$", re.M)
PATCH_MOVE_HEADER = re.compile(r"^\*\*\* Move to:\s+(.+?)\s*$", re.M)
PATCH_ENVELOPE = re.compile(r"\*\*\* Begin Patch.*?(?:\*\*\* End Patch|\Z)", re.S)

SEGMENT_SPLIT = r'\s*(?:&&|\|\||[;|&\n])\s*'


def _resolve(path, cwd):
    if not path:
        return None
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    try:
        return os.path.realpath(path)
    except Exception:
        return None


def _tracks_nothing(path):
    """True when git tracks no file at or under `path`.

    Removing such a path cannot change tracked state, so the guard has nothing
    to protect there — it is not part of the tree. Fails closed: any git error
    reports False and the caller denies as before.
    """
    if not path:
        return False
    try:
        parent = path if os.path.isdir(path) else os.path.dirname(path)
        result = subprocess.run(
            ["git", "-C", parent, "ls-files", "--error-unmatch", "--", path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        if result.returncode == 0:
            return False
        listed = subprocess.run(
            ["git", "-C", parent, "ls-files", "--", path],
            capture_output=True, text=True, timeout=5)
        return listed.returncode == 0 and not listed.stdout.strip()
    except Exception:
        return False


def _effective_cwd(command, cwd):
    """cwd after any leading `cd <dir>` in the command."""
    m = re.search(r'(?:^|[;&|]|&&)\s*cd\s+("[^"]+"|\'[^\']+\'|[^\s;&|]+)', command)
    if not m:
        return cwd
    target = m.group(1).strip('"\'')
    target = os.path.expanduser(target)
    resolved = _resolve(target, cwd)
    return resolved or cwd


def _strip_heredoc_bodies(command):
    """The command with heredoc BODIES removed, keeping a `<<` marker.

    A heredoc body is DATA, not shell syntax, and must not be scanned for
    redirects or paths. The `<<` itself is preserved because rule 4 still
    needs to know a heredoc was present.
    """
    out, i = [], 0
    for m in re.finditer(r'<<-?\s*[\'"]?(\w+)[\'"]?', command):
        tag = m.group(1)
        out.append(command[i:m.end()])
        end = re.search(r'^\s*%s\s*$' % re.escape(tag),
                        command[m.end():], re.M)
        i = m.end() + (end.end() if end else len(command) - m.end())
    out.append(command[i:])
    return "".join(out)


def _unquoted_mask(text):
    """TEXT with every quoted or backslash-escaped character blanked.

    Offsets are preserved, so a match in the mask indexes the original. A `>`
    inside quotes (`grep -o 'ADDR<[0-9A-F]*>'`) is data, not a redirect.
    """
    out = list(text)
    quote = None
    i = 0
    while i < len(text):
        char = text[i]
        if quote:
            if quote == '"' and char == "\\" and i + 1 < len(text):
                out[i] = out[i + 1] = "_"
                i += 2
                continue
            if char == quote:
                quote = None
            else:
                out[i] = "_"
            i += 1
            continue
        if char in ("'", '"'):
            quote = char
        elif char == "\\" and i + 1 < len(text):
            out[i + 1] = "_"
            i += 1
        i += 1
    return "".join(out)


def _redirect_targets(text):
    """Files the shell would open for writing via > or >>.

    TEXT is already heredoc-stripped: a redirect inside a heredoc BODY is data,
    and so is a `>` inside quotes. `->` is NOT a redirect. `>&` (fd
    duplication, e.g. 2>&1) opens no file either, so it is excluded too. A
    substitution inside double quotes still runs, so its body is scanned.
    """
    targets = []
    for m in re.finditer(r'(?<![-&])>>?(?!&)', _unquoted_mask(text)):
        target = re.match(r'\s*("[^"]+"|\'[^\']+\'|[^\s;&|<>]+)', text[m.end():])
        if target:
            targets.append(target.group(1).strip('"\''))
    for body in _shell_substitutions(text):
        targets.extend(_redirect_targets(body))
    return targets


_VARIABLE = re.compile(
    r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
_ASSIGNMENT = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
_DECLARERS = {"export", "local", "declare", "readonly", "typeset"}
_CONTROL_WORDS = {"!", "{", "}", "(", ")", "if", "then", "elif", "else", "fi",
                  "while", "until", "do", "done"}


def _base_env():
    """Variables whose value the hook knows without reading the command."""
    home = os.path.expanduser("~")
    return {"HOME": home} if os.path.isabs(home) else {}


def _substitute(word, env):
    """WORD with tilde and every KNOWN variable expanded; others kept verbatim."""
    if word.startswith("~"):
        word = os.path.expanduser(word)
    return _VARIABLE.sub(
        lambda m: env.get(m.group(1) or m.group(2)) or m.group(0), word)


def _unresolved_at(word):
    """Offset of the first expansion the hook cannot evaluate, else -1."""
    m = re.search(r"[$`]", word)
    return m.start() if m else -1


def _record_assignments(tokens, env):
    """Update ENV with what one shell segment assigns.

    Only a segment made entirely of assignments (optionally behind `export`
    and friends) sets shell state; a value the hook cannot evaluate, a `for`
    loop variable, or a `read` target becomes unknown rather than stale.
    """
    i = 0
    while i < len(tokens) and tokens[i] in _CONTROL_WORDS:
        i += 1
    rest = tokens[i:]
    if len(rest) > 1 and rest[0] == "for":
        env[rest[1]] = None
        return
    if rest and rest[0] == "read":
        for token in rest[1:]:
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", token):
                env[token] = None
        return
    if rest and rest[0] in _DECLARERS:
        rest = [t for t in rest[1:] if not t.startswith("-")]
    assignments = [_ASSIGNMENT.match(t) for t in rest]
    if not rest or not all(assignments):
        return
    for m in assignments:
        value = _substitute(m.group(2), env)
        env[m.group(1)] = value if _unresolved_at(value) == -1 else None


def _segments_with_env(text, env, cwd=None):
    """(segment, variables known, directories it may run in) per segment.

    The directories follow `cd`/`pushd` through the command: a `cd` joined by
    `&&` moves every later command; one joined any other way might have failed,
    so later commands may run in either directory. A subshell's `cd` ends with
    its `)`, and a `cd` inside if/for/while/case/{} leaves both possibilities
    after the block.
    """
    env = dict(env)
    cwds = (cwd,)
    stack = []
    prev_sep = None
    for segment, sep in _shell_segments_sep(text):
        tokens = _tokens(segment)
        mask = _unquoted_mask(segment)
        lead = len(segment) - len(segment.lstrip("( "))
        opens = mask[:lead].count("(")
        for _ in range(opens):
            stack.append(("(", cwds))
        words = [t.lstrip("(") for t in tokens]
        words = [w for w in words if w]
        if words and words[0] in _BLOCK_OPEN:
            stack.append(("block", cwds))
        yield segment, dict(env), cwds
        _record_assignments(tokens, env)
        if cwd is not None and prev_sep != "|" and sep not in ("|", "&"):
            moved = _cd_destinations(words, env, cwds)
            if moved:
                cwds = moved if sep == "&&" else _union(cwds, moved)
        net = (mask.count("(") - opens) - mask.count(")")
        for _ in range(max(net, 0)):
            stack.append(("(", cwds))
        for _ in range(max(-net, 0)):
            if stack:
                kind, saved = stack.pop()
                cwds = saved if kind == "(" else _union(saved, cwds)
        if words and words[0] in _BLOCK_CLOSE and stack:
            _kind, saved = stack.pop()
            cwds = _union(saved, cwds)
        prev_sep = sep


_BLOCK_OPEN = {"if", "while", "until", "for", "case", "select", "{"}
_BLOCK_CLOSE = {"fi", "done", "esac", "}"}


def _union(first, second):
    return tuple(dict.fromkeys(first + second))


def _cd_destinations(words, env, cwds):
    """Directories a `cd`/`pushd` segment moves to; () when not a known move."""
    i = 0
    while i < len(words) and words[i] in _CONTROL_WORDS:
        i += 1
    if i >= len(words) or words[i] not in ("cd", "pushd"):
        return ()
    args = words[i + 1:]
    while args and args[0].startswith("-") and args[0] != "-":
        done = args[0] == "--"
        args = args[1:]
        if done:
            break
    if not args:
        home = _base_env().get("HOME")
        return (home,) if home else ()
    if args[0] == "-" or args[0].startswith("+"):
        return ()
    moved = []
    for here in cwds:
        named = _target(args[0], env, here)
        if not named or named[0] != named[1]:
            return ()
        moved.append(named[0])
    return tuple(dict.fromkeys(moved))


def _target(word, env, cwd):
    """(path, scope) for a shell word naming a file, or None if unknowable.

    PATH is the word with known variables expanded, resolved against CWD.
    SCOPE is the deepest directory the word certainly lies under — PATH itself
    when fully resolved. A word that STARTS with an unknown expansion could be
    anywhere, so it is not guessed to be relative to CWD.
    """
    value = _substitute(word, env)
    cut = _unresolved_at(value)
    if cut == -1:
        path = _resolve(value, cwd)
        return (path, path) if path else None
    prefix = value[:cut]
    if not prefix:
        return None
    path = _resolve(value, cwd)
    scope = _resolve(prefix[:prefix.rfind("/") + 1] or ".", cwd)
    return (path, scope) if path and scope else None


def _tokens(command):
    try:
        return shlex.split(command, comments=False)
    except Exception:
        return command.split()


# `rm x 2>/dev/null` has one target, not two: a redirection is shell syntax,
# not an argument. shlex keeps it as a token, so it has to be dropped here.
_REDIRECT_TOKEN = re.compile(r"^\d*(?:>>|>|<)")


def _redirection(token):
    return bool(_REDIRECT_TOKEN.match(token))


def _leads_with(segment, names):
    """True when SEGMENT invokes one of NAMES as its own command."""
    for tok in _tokens(segment):
        if re.match(r"^[A-Za-z_][A-Za-z_0-9]*=", tok) or tok in ("env", "exec", "command"):
            continue
        return os.path.basename(tok) in names
    return False


def _leads_with_sanctioned_tool(segment):
    """True when SEGMENT invokes a sanctioned tool as its own command."""
    return _leads_with(segment, SANCTIONED_TOOLS)


def _excise_sanctioned(text):
    """TEXT with sanctioned-tool segments dropped.

    Per SEGMENT, never per command: `wt-rescue x && git -C main reset --hard`
    still gets its second half scanned. Separators are kept verbatim — the
    segment split cuts through `2>&1`, so rejoining without them would forge a
    redirect out of an fd duplication.
    """
    parts = re.split("(" + SEGMENT_SPLIT + ")", text)
    return "".join(p for i, p in enumerate(parts)
                   if i % 2 or not _leads_with_sanctioned_tool(p))


def _patch_targets(envelope):
    """Raw file targets named by one apply_patch envelope."""
    return (PATCH_FILE_HEADER.findall(envelope)
            + PATCH_MOVE_HEADER.findall(envelope))


def _patch_removal_targets(envelope):
    """Targets deleted or moved away, which may be live pin metadata."""
    removed = []
    blocks = re.split(
        r"(?=^\*\*\* (?:Add|Update|Delete) File:)", envelope, flags=re.M)
    for block in blocks:
        deleted = re.match(r"^\*\*\* Delete File:\s+(.+?)\s*$", block, re.M)
        if deleted:
            removed.append(deleted.group(1))
            continue
        updated = re.match(r"^\*\*\* Update File:\s+(.+?)\s*$", block, re.M)
        if updated and PATCH_MOVE_HEADER.search(block):
            removed.append(updated.group(1))
    return removed


def _find_envelope(value):
    """The first nested string containing an apply_patch envelope."""
    if isinstance(value, str):
        return value if PATCH_BEGIN in value else None
    if isinstance(value, dict):
        for child in value.values():
            found = _find_envelope(child)
            if found is not None:
                return found
    return None


def _invokes_apply_patch(stripped_text):
    """True when a shell segment invokes apply_patch as its command."""
    return any(_leads_with(segment, {"apply_patch"})
               for segment in re.split(SEGMENT_SPLIT, stripped_text))


def _apply_patch_fail_closed():
    return (
        "This apply_patch call is denied fail-closed: a patch whose targets "
        "cannot be read cannot be checked. Re-issue it with well-formed "
        "`*** Add/Update/Delete File:` headers. Deliberate bypass: "
        "`north config agents off launch-critical-worktree-guard`.")


def _apply_patch_target_decision(targets, cwd, removal_targets=()):
    for target in removal_targets:
        path = _resolve(os.path.expanduser(target), cwd)
        sidecar = pin_sidecar(path)
        if sidecar:
            container, name, _pin_path = sidecar
            return (
                f"This apply_patch envelope would delete live pin consumer "
                f"metadata at {path}. Retire the checkout and sidecar together "
                f"after proving every named consumer moved:\n\n"
                f"  pin-retire --consumer-main CONSUMER/main -- "
                f"{os.path.join(code_root(), container, 'pins', name)}")
    for target in targets:
        path = _resolve(os.path.expanduser(target), cwd)
        hit = protected_project(path)
        if hit:
            project, why, kind = hit
            return (f"This apply_patch envelope would write {path} inside "
                    f"{hit_noun(project, kind)}. {why}\n\n"
                    f"{hit_advice(project, kind)}")
    return None


def _apply_patch_tool_decision(tool_input, payload):
    """Decision for a direct apply_patch tool call."""
    cwd = payload.get("cwd") or os.getcwd()
    if isinstance(tool_input, dict):
        explicit = [tool_input.get(key) for key in ("file_path", "path")]
        verdict = _apply_patch_target_decision(
            [value for value in explicit if isinstance(value, str)], cwd)
        if verdict:
            return verdict
        selected_cwd = tool_input.get("workdir") or tool_input.get("cwd")
        patch_cwd = selected_cwd if isinstance(selected_cwd, str) else cwd
    else:
        patch_cwd = cwd

    envelope = _find_envelope(tool_input)
    if envelope is None:
        return _apply_patch_fail_closed()
    targets = _patch_targets(envelope)
    if not targets:
        return _apply_patch_fail_closed()
    return _apply_patch_target_decision(
        targets, patch_cwd, _patch_removal_targets(envelope))


def _apply_patch_command_decision(command, cwd, stripped=None):
    """Decision for apply_patch invoked through a shell string or argv."""
    if isinstance(command, str):
        stripped = stripped if stripped is not None else _strip_heredoc_bodies(command)
        invoked = _invokes_apply_patch(stripped)
        envelopes = PATCH_ENVELOPE.findall(command)
    elif isinstance(command, list):
        invoked = bool(command and os.path.basename(command[0]) == "apply_patch")
        if (not invoked and command
                and os.path.basename(command[0]) in {"bash", "sh", "zsh"}):
            for i, flag in enumerate(command[1:-1], start=1):
                if flag.startswith("-") and "c" in flag[1:]:
                    inner = command[i + 1]
                    invoked = _invokes_apply_patch(_strip_heredoc_bodies(inner))
                    break
        envelopes = PATCH_ENVELOPE.findall("\n".join(command))
    else:
        return None

    if not invoked:
        return None
    if not envelopes:
        return _apply_patch_fail_closed()
    for envelope in envelopes:
        targets = _patch_targets(envelope)
        if not targets:
            return _apply_patch_fail_closed()
        verdict = _apply_patch_target_decision(
            targets, cwd, _patch_removal_targets(envelope))
        if verdict:
            return verdict
    return None


def _shell_segments(text):
    """Split live shell commands without treating quoted separators as syntax."""
    return [segment for segment, _sep in _shell_segments_sep(text)]


def _shell_segments_sep(text):
    """(segment, separator that follows it) for each live shell command.

    The separator is `&&`, `||`, `|`, `&`, or `;` (a newline counts as `;`);
    the last segment has None. Which one follows a `cd` decides whether the
    next command certainly runs in the new directory.
    """
    segments, buf = [], []
    quote = None
    i = 0
    while i < len(text):
        char = text[i]
        if quote:
            buf.append(char)
            if quote == '"' and char == "\\" and i + 1 < len(text):
                i += 1
                buf.append(text[i])
            elif char == quote:
                quote = None
            i += 1
            continue
        if char in ("'", '"'):
            quote = char
            buf.append(char)
            i += 1
            continue
        if char == "\\" and i + 1 < len(text):
            buf.append(char)
            i += 1
            buf.append(text[i])
            i += 1
            continue
        if char in ";|&\n":
            sep = ";" if char == "\n" else char
            if i + 1 < len(text) and text[i:i + 2] in ("&&", "||"):
                sep = text[i:i + 2]
                i += 1
            segment = "".join(buf).strip()
            if segment:
                segments.append((segment, sep))
            buf = []
            i += 1
            continue
        buf.append(char)
        i += 1
    segment = "".join(buf).strip()
    if segment:
        segments.append((segment, None))
    return segments


def _shell_substitutions(text):
    """Executable bodies of `$()` and backticks, excluding single-quoted data."""
    bodies = []
    quote = None
    i = 0
    while i < len(text):
        char = text[i]
        if quote == "'":
            if char == "'":
                quote = None
            i += 1
            continue
        if char == "\\" and i + 1 < len(text):
            i += 2
            continue
        if char == '"':
            quote = None if quote == '"' else '"'
            i += 1
            continue
        if char == "'" and quote is None:
            quote = "'"
            i += 1
            continue
        if char == "`":
            j = i + 1
            body = []
            while j < len(text):
                if text[j] == "\\" and j + 1 < len(text):
                    body.extend((text[j], text[j + 1]))
                    j += 2
                    continue
                if text[j] == "`":
                    bodies.append("".join(body))
                    i = j + 1
                    break
                body.append(text[j])
                j += 1
            else:
                i += 1
            continue
        if char == "$" and i + 1 < len(text) and text[i + 1] == "(":
            # `$((...))` is arithmetic, not a command substitution.
            if i + 2 < len(text) and text[i + 2] == "(":
                i += 3
                continue
            depth, nested_quote, j = 1, None, i + 2
            while j < len(text):
                nested = text[j]
                if nested_quote:
                    if nested_quote == '"' and nested == "\\" and j + 1 < len(text):
                        j += 2
                        continue
                    if nested == nested_quote:
                        nested_quote = None
                    j += 1
                    continue
                if nested in ("'", '"'):
                    nested_quote = nested
                elif nested == "\\" and j + 1 < len(text):
                    j += 2
                    continue
                elif nested == "(":
                    depth += 1
                elif nested == ")":
                    depth -= 1
                    if depth == 0:
                        bodies.append(text[i + 2:j])
                        i = j + 1
                        break
                j += 1
            else:
                i += 2
            continue
        i += 1
    return bodies


def _shell_command_index(tokens):
    """Index of the executable after common shell wrappers and assignments."""
    i = 0
    wrappers = {"env", "command", "builtin", "exec", "nohup", "sudo", "time"}
    controls = {"!", "{", "if", "then", "elif", "while", "until", "do"}
    value_flags = {
        "env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"},
        "sudo": {
            "-u", "--user", "-g", "--group", "-h", "--host", "-p",
            "--prompt", "-C", "--chdir", "-r", "--role", "-t", "--type",
        },
    }
    while i < len(tokens):
        word = os.path.basename(tokens[i]).lstrip("(")
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i]):
            i += 1
            continue
        if word in controls:
            i += 1
            continue
        if word not in wrappers:
            break
        i += 1
        consumes = value_flags.get(word, set())
        while i < len(tokens):
            arg = tokens[i]
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", arg):
                i += 1
            elif arg in consumes and i + 1 < len(tokens):
                i += 2
            elif arg == "--":
                i += 1
                break
            elif arg.startswith("-"):
                i += 1
            else:
                break
    return i


def _cargo_target_paths(text):
    """Literal Cargo target paths selected by directly invoked cargo commands.

    The Bash entrance exposes a command string, so only shell forms whose
    executable and target path are mechanically decidable are covered: an
    inline CARGO_TARGET_DIR assignment (including through `env`) and Cargo's
    `--target-dir PATH` / `--target-dir=PATH` option. Variable-expanded or
    indirect shell state remains fail-open.
    """
    paths = []
    for segment in _shell_segments(text):
        tokens = _tokens(segment)
        executable_index = _shell_command_index(tokens)
        if (executable_index >= len(tokens)
                or os.path.basename(tokens[executable_index]).lstrip("(") != "cargo"):
            continue
        for token in tokens[:executable_index]:
            if token.startswith("CARGO_TARGET_DIR="):
                value = token.split("=", 1)[1]
                if value and "$" not in value:
                    paths.append(value)
        args = tokens[executable_index + 1:]
        i = 0
        while i < len(args):
            argument = args[i]
            if argument == "--target-dir" and i + 1 < len(args):
                value = args[i + 1]
                if value and "$" not in value:
                    paths.append(value)
                i += 2
                continue
            if argument.startswith("--target-dir="):
                value = argument.split("=", 1)[1]
                if value and "$" not in value:
                    paths.append(value)
            i += 1
    return paths


def _shell_c_script(tokens, executable_index):
    """The command string executed by a shell's `-c` option, if present."""
    i = executable_index + 1
    while i < len(tokens):
        arg = tokens[i]
        if arg in {"-O", "-o"} and i + 1 < len(tokens):
            i += 2
            continue
        if arg.startswith("-") and not arg.startswith("--") and "c" in arg[1:]:
            i += 1
            if i < len(tokens) and tokens[i] == "--":
                i += 1
            return tokens[i] if i < len(tokens) else None
        if arg == "--" or arg.startswith("-"):
            i += 1
            continue
        return None
    return None


def _git_invocations(text, cwd, env=None):
    """(target, verb, args) for EVERY git call in TEXT.

    Split per segment first: one sanctioned git call must not vouch for a
    mutating one later in the same line.
    """
    found = []
    # shlex preserves quoted arguments as single tokens. Thus `git -C
    # "<pin>" checkout REF` retains its target, while quoted prose such as
    # `printf 'git -C <pin> checkout REF'` never manufactures a `git` token.
    for segment, seg_env, seg_cwds in _segments_with_env(
            text, _base_env() if env is None else env, cwd):
        tokens = _tokens(segment)
        command_index = _shell_command_index(tokens)
        for here in seg_cwds:
            found.extend(_git_calls(tokens, command_index, seg_env, here))
            for body in _shell_substitutions(segment):
                found.extend(_git_invocations(body, here, seg_env))
    return found


def _git_calls(tokens, command_index, env, cwd):
    """(target, verb, args) for the git calls in one segment run from CWD."""
    found = []
    for i, tok in enumerate(tokens):
        executable = os.path.basename(tok).lstrip("(")
        if executable in {"sh", "bash", "zsh"} and i == command_index:
            script = _shell_c_script(tokens, i)
            if script:
                found.extend(_git_invocations(script, cwd, env))
        if executable != "git":
            continue
        rest = tokens[i + 1:]
        target, verb, j = cwd, None, 0
        while j < len(rest):
            t = rest[j]
            if t == "-C" and j + 1 < len(rest):
                # Each -C is relative to the previous one, as git applies them.
                named = _target(rest[j + 1], env, target) if target else None
                target = named[0] if named else None
                j += 2
                continue
            if t.startswith("-"):
                j += 1
                continue
            verb = t
            break
        if verb and target:
            found.append((target, verb, rest[j + 1:]))
    return found


def _short_letters(flags):
    """The letters of clustered short flags: -fd -> {f, d}."""
    return {c for f in flags if re.match(r"^-[A-Za-z]+$", f) for c in f[1:]}


def _git_read_form(verb, args):
    """True when a mutating verb was called in a form that only reports."""
    flags = [a for a in args if a.startswith("-")]
    plain = [a for a in args if not a.startswith("-")]
    if verb == "stash":
        return (plain[0] if plain else "push") in STASH_READS
    if verb == "clean":
        return "--dry-run" in flags or "n" in _short_letters(flags)
    return False


def _worktree_positionals(args):
    """Return a worktree subcommand and its path-like positional arguments."""
    if not args:
        return None, []
    subcommand = None
    rest = []
    for i, arg in enumerate(args):
        if not arg.startswith("-"):
            subcommand = arg
            rest = args[i + 1:]
            break
    if not subcommand:
        return None, []

    positionals = []
    skip_value = False
    value_flags = {"-b", "-B", "--reason"}
    literal = False
    for arg in rest:
        if skip_value:
            skip_value = False
            continue
        if literal:
            positionals.append(arg)
            continue
        if arg == "--":
            literal = True
            continue
        if arg in value_flags:
            skip_value = True
            continue
        if arg.startswith("--reason=") or arg.startswith("-"):
            continue
        positionals.append(arg)
    return subcommand, positionals


def _stray_nested_worktree(target, args, path, hit):
    """True for a non-forced remove of a registered linked worktree inside main/.

    Agents sometimes create lanes with a relative path, landing them under
    main/. Git itself refuses to remove a dirty worktree without --force.
    """
    if hit[2] != MAIN_KIND or any(a in ("-f", "--force") for a in args):
        return False
    try:
        out = subprocess.run(
            ["git", "-C", target, "worktree", "list", "--porcelain"],
            capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return False
    listed = [os.path.realpath(line[len("worktree "):])
              for line in out.splitlines() if line.startswith("worktree ")]
    return bool(listed) and path != listed[0] and path in listed[1:]


def _worktree_decision(target, args):
    """Affected protected path for a disallowed worktree mutation, else None."""
    subcommand, paths = _worktree_positionals(args)
    if subcommand == "add":
        hit = protected_project(target)
        if hit and is_pin(hit[2]):
            return (target, "worktree add from an immutable pin")
        # A relative lane path run from inside main/ lands the lane in main/,
        # where this guard then refuses every later write and removal.
        if paths:
            path = _resolve(os.path.expanduser(paths[0]), target)
            hit = protected_project(path)
            if hit and not (is_pin(hit[2]) and os.path.basename(
                    os.path.dirname(os.path.realpath(path))) == "pins"):
                return (path, "worktree add")
        return None
    if subcommand in {"remove", "move"}:
        affected = paths[:1] if subcommand == "remove" else paths[:2]
        for raw in affected:
            path = _resolve(os.path.expanduser(raw), target)
            hit = protected_project(path)
            if hit and not (subcommand == "remove"
                            and _stray_nested_worktree(target, args, path, hit)):
                return (path, "worktree " + subcommand)
        return None
    # list/prune/lock/unlock/repair do not change checkout bytes or HEAD.
    return None


def _git_decisions(invocations):
    """Yield every path-affecting mutating git call in command order."""
    for target, verb, args in invocations:
        if verb == "worktree":
            decision = _worktree_decision(target, args)
            if decision:
                yield decision
            continue
        if verb in SANCTIONED_GIT or _git_read_form(verb, args):
            continue
        if verb in FF_ONLY_GIT:
            # Only the fast-forward form is sanctioned; a bare merge/pull can
            # conflict and leave the checkout dirty, which is the whole problem.
            if "--ff-only" in args:
                continue
            yield (target, verb + " (without --ff-only)")
            continue
        if verb in MUTATING_GIT:
            yield (target, verb)


def _wip_destroying(verb, args):
    """A short label when this git call discards uncommitted work, else None."""
    flags = [a for a in args if a.startswith("-")]
    plain = [a for a in args if not a.startswith("-")]

    if verb == "reset":
        for f in ("--hard", "--merge", "--keep"):
            if f in flags:
                return "git reset " + f
        return None
    if verb == "stash":
        sub = plain[0] if plain else "push"
        return None if sub in STASH_READS else "git stash " + sub
    if verb == "checkout":
        # Restoring paths overwrites the working tree; switching branches does
        # not, and is caught as an ordinary mutation instead.
        if "--" in args or "." in plain or "-f" in flags or "--force" in flags:
            return "git checkout of working-tree paths"
        return None
    if verb == "restore":
        # --staged alone only unstages; anything else rewrites the working tree.
        if "--staged" in flags and "--worktree" not in flags:
            return None
        return "git restore"
    if verb == "clean":
        if _git_read_form(verb, args):
            return None
        if "--force" in flags or "f" in _short_letters(flags):
            return "git clean -f"
        return None
    return None


def decide(payload):
    """A deny reason string, or None to allow."""
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}

    # --- apply_patch ----------------------------------------------------------
    if tool.endswith("apply_patch"):
        return _apply_patch_tool_decision(tool_input, payload)

    # --- Edit / Write / MultiEdit: the original, unchanged behaviour ---------
    if tool != "Bash":
        path = tool_input.get("file_path")
        hit = protected_project(path)
        if not hit:
            return None
        project, why, kind = hit
        return (f"{path} is inside {hit_noun(project, kind)}. {why}"
                f"\n\n{hit_advice(project, kind)}")

    # --- Bash ----------------------------------------------------------------
    command = tool_input.get("command")
    if isinstance(command, list) and all(isinstance(x, str) for x in command):
        verdict = _apply_patch_command_decision(
            command, payload.get("cwd") or os.getcwd())
        if verdict:
            return verdict
        return None
    if not isinstance(command, str) or not command:
        return None
    cwd = payload.get("cwd") or os.getcwd()
    eff = _effective_cwd(command, cwd)
    # Every rule scans this, not the raw command. Heredoc bodies are stripped
    # because a `sed -i /path` or `rm /path` in heredoc data is text being
    # written, not a command being run; sanctioned-tool segments are excised
    # because their remediation is the compliant move.
    scan = _excise_sanctioned(_strip_heredoc_bodies(command))
    def deny(path, project, why, what, kind=None):
        return (f"This Bash command would {what} inside "
                f"{hit_noun(project, kind)} ({path}). {why}\n\n"
                f"{hit_advice(project, kind)}\n"
                f"Reads are fine — it is the write that is refused.")

    verdict = _apply_patch_command_decision(command, eff, scan)
    if verdict:
        return verdict

    tokens = _tokens(scan)
    invocations = _git_invocations(scan, cwd)
    segments = list(_segments_with_env(scan, _base_env(), cwd))
    # A substitution body is cut apart by the segment split, so bodies are
    # taken from the whole command and scanned with the variables known at
    # its end.
    final_env = dict(segments[-1][1]) if segments else _base_env()
    if segments:
        _record_assignments(_tokens(segments[-1][0]), final_env)
    # The whole-command split cannot say which segment a body sat in, so a
    # body may run in any directory the command visits.
    visited = ()
    for _segment, _env, seg_cwds in segments:
        visited = _union(visited, seg_cwds)
    nested = [(segment, seg_env, inner)
              for body in _shell_substitutions(scan)
              for here in visited or (cwd,)
              for segment, seg_env, inner in _segments_with_env(
                  body, final_env, here)]

    # Cargo output belongs to the exact lane that produced it. A literal
    # target path in a main or pin is already protected; a path in a fourth
    # top-level container slot is the root-level target-* spill this rule adds.
    for raw in _cargo_target_paths(scan):
        resolved = _resolve(os.path.expanduser(raw), eff)
        hit = protected_project(resolved)
        if hit:
            project, why, kind = hit
            return deny(resolved, project, why, "write Cargo target output", kind)
        container = repository_container_spill(resolved)
        if container:
            lane_target = os.path.join(
                code_root(), container, "worktrees", "SLUG", "target")
            return (
                f"This Bash command would put Cargo target output directly in "
                f"the repository container {os.path.join(code_root(), container)} "
                f"({resolved}). Build output belongs to the exact lane that "
                f"produced it. Use the lane-local default, set "
                f"`CARGO_TARGET_DIR={lane_target}`, or use a deliberate /tmp "
                f"target outside repository containers.")

    # 0. destroying uncommitted work in a main checkout — its own class, because
    #    the loss is the human's and is not recoverable from the ref. A pin has
    #    no human WIP to lose; it answers with the pin's own reason and remedy,
    #    because `wt-rescue` is the wrong move against an externally consumed
    #    checkout.
    for target, verb, args in invocations:
        what = _wip_destroying(verb, args)
        if not what:
            continue
        hit = protected_project(target)
        if hit and is_pin(hit[2]):
            project, why, kind = hit
            return (f"`{what}` targets {target}, {hit_noun(project, kind)}. "
                    f"{why}\n\n{hit_advice(project, kind)}")
        if hit:
            project, why, _kind = hit
            return (
                f"`{what}` targets {target}, the MAIN checkout of {project}. "
                f"Uncommitted state in a main checkout is the human's "
                f"work-in-progress; an agent never discards it. {why}\n\n"
                f"Compliant moves:\n"
                f"  git -C {target} status --porcelain   # inspect, do not discard\n"
                f"  wt-rescue {target}\n"
                f"  # dirty main? run `wt-rescue` (relocates intact, restores clean)\n"
                f"  # rare surgery only: `north config agents off launch-critical-worktree-guard` — deliberate\n"
                f"  # bypass, state why, re-enable after\n"
                f"{worktree_advice(project)}")

    # 1. mutating git, wherever it points
    for target, verb in _git_decisions(invocations):
        hit = protected_project(target)
        if hit:
            project, why, kind = hit
            return deny(target, project, why, f"run `git {verb}`", kind)

    # 2. shell redirection into a protected path
    for segment, seg_env, seg_cwds in segments:
        for raw in _redirect_targets(segment):
            for here in seg_cwds:
                named = _target(raw, seg_env, here)
                hit = protected_project(named[0]) if named else None
                if hit:
                    project, why, kind = hit
                    return deny(named[0], project, why, "write", kind)

    # 3. in-place / destination-taking commands, per SEGMENT.
    #    `cp`/`mv`/`ln` take their destination as the LAST argument — but only
    #    within their own command. Scanning to the end of a compound command
    #    made `ln -s a b; echo "(none = clean)"` treat the echo's text as ln's
    #    destination and deny it. Split on shell separators first.
    for segment, seg_env, seg_cwds in segments + nested:
        for here in seg_cwds:
            found = _scan_write_commands(_tokens(segment), here, deny, seg_env)
            if found:
                return found

    # 4. an interpreter fed a heredoc, while cwd is a protected checkout. The
    #    written path lives inside the script and cannot be parsed out, so this
    #    is refused on cwd alone; running it from elsewhere with absolute paths
    #    is unaffected.
    hit = protected_project(eff)
    if hit and "<<" in scan:
        for tok in tokens:
            if os.path.basename(tok) in INTERPRETERS:
                return deny(eff, hit[0], hit[1],
                            "run an interpreter script with its working directory",
                            hit[2])
    return None


def _scan_write_commands(tokens, eff, deny, env):
    lead = os.path.basename(tokens[0]) if tokens else ""
    package_manager = lead in PACKAGE_MANAGERS
    command_index = _shell_command_index(tokens)
    if (command_index < len(tokens)
            and os.path.basename(tokens[command_index]) in READ_ONLY_COMMANDS):
        return None

    def located(word):
        named = _target(word, env, eff)
        return named[0] if named else None

    for i, tok in enumerate(tokens):
        base = os.path.basename(tok)
        if package_manager and i > 0:
            continue
        args = [a for a in tokens[i + 1:]
                if not a.startswith("-") and not _redirection(a)]
        if base == "sed" and any(a.startswith("-i") for a in tokens[i + 1:]):
            for a in args[1:]:
                hit = protected_project(located(a))
                if hit:
                    return deny(a, hit[0], hit[1], "edit in place", hit[2])
        elif base in WRITE_COMMANDS or base in DESTRUCTIVE_COMMANDS:
            for a in args:
                named = _target(a, env, eff)
                if not named:
                    continue
                resolved, scope = named
                sidecar = pin_sidecar(resolved)
                if base in DESTRUCTIVE_COMMANDS and sidecar:
                    container, name, pin_path = sidecar
                    hit = protected_project(pin_path)
                    if hit:
                        return deny(
                            resolved, hit[0], hit[1],
                            f"delete live consumer metadata with `{base}`; use "
                            f"`pin-retire --consumer-main CONSUMER/main -- "
                            f"{pin_path}` instead",
                            hit[2])
                hit = protected_project(resolved)
                if hit:
                    # A gitignored build artifact inside a PIN is still the pin's:
                    # it is protected because a consumer reads the tree, not
                    # because git tracks the bytes.
                    if (base in DESTRUCTIVE_COMMANDS and not is_pin(hit[2])
                            and _tracks_nothing(scope)):
                        continue
                    return deny(a, hit[0], hit[1], f"run `{base}`", hit[2])
        elif base in COPY_COMMANDS and args:
            if base == "mv":
                for source in args[:-1]:
                    resolved = located(source)
                    sidecar = pin_sidecar(resolved)
                    if sidecar:
                        _container, _name, pin_path = sidecar
                        hit = protected_project(pin_path)
                        if hit:
                            return deny(
                                resolved, hit[0], hit[1],
                                "move live consumer metadata; use "
                                f"`pin-retire --consumer-main CONSUMER/main -- "
                                f"{pin_path}` instead",
                                hit[2])
            dest = args[-1]
            hit = protected_project(located(dest))
            if hit:
                return deny(dest, hit[0], hit[1], f"run `{base}` into", hit[2])
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    try:
        reason = decide(payload)
    except Exception:
        return 0  # fail-open
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
