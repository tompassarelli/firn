"""Blanking keeps offsets for regex command-position anchors; tokenizing splits with shlex."""

import os
import re
import shlex

_HEREDOC_START = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")
_HEREDOC_BODY = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)^[ \t]*\2[ \t]*$", re.S | re.M)
SEPARATORS = ";&|()\n"
_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_DURATION = re.compile(r"^[0-9.]+[smhd]?$")


def blank(text):
    return "".join(c if c == "\n" else " " for c in text)


def strip_heredocs(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        m = _HEREDOC_START.search(s, i)
        if not m:
            out.append(s[i:])
            break
        out.append(s[i:m.end()])
        line_end = s.find("\n", m.end())
        if line_end == -1:
            out.append(s[m.end():])
            break
        out.append(s[m.end():line_end + 1])
        body_start = line_end + 1
        term = re.compile(r"^[ \t]*" + re.escape(m.group(2)) + r"[ \t]*$", re.M)
        tm = term.search(s, body_start)
        if tm:
            out.append(blank(s[body_start:tm.start()]))
            i = tm.start()
        else:
            out.append(blank(s[body_start:]))
            i = n
    return "".join(out)


def strip_quotes(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == "'":
            j = s.find("'", i + 1)
            end = n if j == -1 else j + 1
            out.append(blank(s[i:end]))
            i = end
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\" and j + 1 < n:
                    j += 2
                    continue
                if s[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(blank(s[i:j]))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def words(cmd):
    text = _HEREDOC_BODY.sub(lambda m: m.group(0)[: m.start(3) - m.start(0)] + m.group(2), cmd)
    try:
        lexer = shlex.shlex(text, posix=True, punctuation_chars=SEPARATORS)
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        lexer.commenters = "#"
        return list(lexer)
    except ValueError:
        return None


def is_separator(token):
    return bool(token) and set(token) <= set(SEPARATORS)


def segments(tokens):
    segment = []
    for token in tokens + [";"]:
        if is_separator(token):
            yield segment
            segment = []
        else:
            segment.append(token)


def command(segment, prefixes):
    index = 0
    while index < len(segment):
        word = segment[index]
        name = os.path.basename(word)
        if _ASSIGNMENT.match(word) or word == "--" or (word.startswith("-") and index > 0):
            index += 1
            continue
        if name in prefixes:
            index += 1
            if name == "timeout" and index < len(segment) and _DURATION.match(segment[index]):
                index += 1
            continue
        break
    return index
