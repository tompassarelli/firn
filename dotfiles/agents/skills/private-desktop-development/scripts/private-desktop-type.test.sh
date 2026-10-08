#!/usr/bin/env bash
set -euo pipefail
# Run with python3 on PATH; checks the key plan only and never opens VNC.
cd -- "$(dirname -- "$(realpath -- "$0")")"
python3 - <<'PY'
import importlib.util, string
spec = importlib.util.spec_from_file_location("typer", "private-desktop-type.py")
typer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(typer)
SHIFT = True
expected = {c: (False, c) for c in string.ascii_lowercase + string.digits + " `-=[]\\;',./"}
expected.update({c: (SHIFT, c) for c in string.ascii_uppercase})
expected.update({c: (SHIFT, c) for c in '~!@#$%^&*()_+{}|:"<>?'})
expected.update({"\n": (False, "enter"), "\t": (False, "tab")})
printable = set(string.printable) - set("\r\x0b\x0c")
assert set(expected) == printable, sorted(printable ^ set(expected))
for character, key in expected.items():
    assert typer.plan(character) == [key], (character, typer.plan(character), key)
assert typer.plan("Ab@#1x.Z_-+") == [expected[c] for c in "Ab@#1x.Z_-+"]
for bad in ("é", "\r", "€", "a\x00"):
    try:
        typer.plan(bad)
    except ValueError:
        continue
    raise AssertionError(f"accepted {bad!r}")
print(f"PASS: private-desktop type maps {len(expected)} characters; non-US text refused")
PY
