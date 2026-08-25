#!/usr/bin/env python3
"""The guard must refuse the Bash calls that actually breached the primaries.

The DENY cases in the first section are verbatim command shapes an agent ran
against a launch-critical primary on 2026-07-29 while the guard was live and
wired. None of them fired, because the guard only inspected
`tool_input.file_path`, which a Bash call does not have. These cases exist so
that hole cannot reopen. Later sections cover every protected `main` and the
WIP-destroying git verbs.

The ALLOW cases matter just as much: a guard that also blocks reads, or blocks
`git worktree add` — the very escape route its deny message recommends — traps
the agent with no compliant move, and the next person turns the guard off.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DECIDE = os.path.join(HERE, "lib", "launch_critical_decide.py")

failures = []
checks = 0


def run(payload, code_root=None):
    env = dict(os.environ)
    if code_root:
        env["LAUNCH_CRITICAL_CODE_ROOT"] = code_root
    else:
        env.pop("LAUNCH_CRITICAL_CODE_ROOT", None)
    p = subprocess.run([sys.executable, DECIDE], input=json.dumps(payload),
                       capture_output=True, text=True, timeout=30, env=env)
    out = p.stdout.strip()
    if not out:
        return None
    return json.loads(out)["hookSpecificOutput"]["permissionDecisionReason"]


def bash(command, cwd="/home/tom"):
    return {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd}


def patch(envelope, cwd="/home/tom", key="input", tool="apply_patch", extra=None):
    ti = {key: envelope}
    if extra:
        ti.update(extra)
    return {"tool_name": tool, "tool_input": ti, "cwd": cwd}


ENV = "*** Begin Patch\n*** {verb} File: {path}\n{body}*** End Patch"


def check(label, condition):
    global checks
    checks += 1
    if condition:
        print("  PASS ", label)
    else:
        failures.append(label)
        print("  FAIL ", label)


NORTH = "/home/tom/code/north/main"
BEAGLE = "/home/tom/code/beagle/main"

print("--- must DENY: what actually happened on 2026-07-29 ---")

check("heredoc patch with cwd in the north primary",
      run(bash("python3 - <<'PYEOF'\nopen('cli/x.clj','w')\nPYEOF", cwd=NORTH)))

check("git add from inside the north primary",
      run(bash("git add cli/x.clj", cwd=NORTH)))

check("git commit from inside the north primary",
      run(bash("git commit -q -m 'x'", cwd=NORTH)))

check("git reset --hard against the beagle primary via -C",
      run(bash("git -C /home/tom/code/beagle/main reset --hard origin/main")))

check("git add of many paths from inside the beagle primary",
      run(bash("FILES=$(cat list); git add $FILES", cwd=BEAGLE)))

check("git push from inside the primary",
      run(bash("git push origin main", cwd=NORTH)))

check("redirection into a primary file",
      run(bash("echo x > /home/tom/code/north/main/cli/x.clj")))

check("sed -i against a primary file",
      run(bash("sed -i s/a/b/ /home/tom/code/beagle/main/bin/beagle")))

check("cp INTO a primary",
      run(bash("cp /tmp/x.clj /home/tom/code/north/main/cli/x.clj")))

check("rm inside a primary",
      run(bash("rm /home/tom/code/beagle/main/bin/beagle")))

check("cd into a primary then write, in one command",
      run(bash("cd /home/tom/code/north/main && echo x > cli/x.clj")))

check("the deny names the project", "north" in (run(bash("git add .", cwd=NORTH)) or ""))
check("the deny gives the worktree escape route",
      "worktree add" in (run(bash("git add .", cwd=NORTH)) or ""))

print("--- must ALLOW: reads, and the sanctioned way out ---")

check("git log against a primary", run(bash("git -C /home/tom/code/north/main log --oneline -1")) is None)
check("git status against a primary", run(bash("git status --porcelain", cwd=NORTH)) is None)
check("git diff against a primary", run(bash("git -C /home/tom/code/beagle/main diff --stat")) is None)
check("grep inside a primary", run(bash("grep -rn foo cli/", cwd=NORTH)) is None)
check("cat a primary file", run(bash("cat /home/tom/code/north/main/cli/coord.clj")) is None)

check("git worktree add FROM the primary is the escape route, never blocked",
      run(bash("git -C /home/tom/code/north/main worktree add "
               "/home/tom/code/north/worktrees/x -b x")) is None)
check("the advised mkdir + worktree add sequence is allowed end to end",
      run(bash("mkdir -p /home/tom/code/north/worktrees && "
               "git -C /home/tom/code/north/main worktree add "
               "/home/tom/code/north/worktrees/x -b x")) is None)
check("git fetch INTO the primary is allowed",
      run(bash("git -C /home/tom/code/north/main fetch "
               "/home/tom/code/north/worktrees/x x:refs/heads/main")) is None)

# THE LANDING PATH MUST WORK. `fetch <wt> <branch>:refs/heads/main` fails when
# main is checked out — which it always is under this layout — so --ff-only
# merge/pull is the only way work can reach main. A guard that blocks the one
# compliant landing move is a guard that gets switched off.
check("merge --ff-only into the primary is the landing path",
      run(bash("git -C /home/tom/code/north/main merge --ff-only feature")) is None)
check("pull --ff-only into the primary is allowed",
      run(bash("git -C /home/tom/code/north/main pull --ff-only")) is None)
check("a BARE merge into the primary is still denied (can conflict, can dirty)",
      run(bash("git -C /home/tom/code/north/main merge feature")))
check("a BARE pull into the primary is still denied",
      run(bash("git -C /home/tom/code/north/main pull")))

# FALSE POSITIVES. Each of these was a real denial this guard produced against
# legitimate work on 2026-07-29, and each one is a reason someone would switch
# it off. A guard that cries wolf is worse than no guard.
check("an arrow inside a quoted string is not a redirect",
      run(bash('echo "north/bin -> needs compat"', cwd=NORTH)) is None)
check("fd duplication (2>&1) opens no file",
      run(bash("grep -rn foo cli/ 2>&1 | head", cwd=NORTH)) is None)
check("a redirect inside a HEREDOC BODY is data, not shell syntax",
      run(bash("cat > /tmp/t.py <<'EOF'\ncheck('echo x > /home/tom/code/north/main/cli/x.clj')\nEOF")) is None)
check("sed -i inside a heredoc body is data, not a command",
      run(bash("cat > /tmp/t.sh <<'EOF'\nsed -i s/a/b/ /home/tom/code/beagle/main/bin/beagle\nEOF")) is None)

# ...while the real forms are still refused.
check("a REAL redirect into a primary is still denied",
      run(bash("echo x > /home/tom/code/north/main/cli/zz.clj")))
check("a REAL sed -i on a primary is still denied",
      run(bash("sed -i s/a/b/ /home/tom/code/beagle/main/bin/beagle")))

check("redirect to /tmp while cwd is a primary is fine",
      run(bash("grep foo cli/x.clj > /tmp/out", cwd=NORTH)) is None)

print("--- the worktrees/ carve-out — the PARENT directory, positionally ---")

check("writing in a lane is allowed",
      run(bash("git add .", cwd="/home/tom/code/north/worktrees/abc")) is None)
check("heredoc in a lane is allowed",
      run(bash("python3 - <<'EOF'\npass\nEOF",
               cwd="/home/tom/code/north/worktrees/abc")) is None)
check("a lane whose slug is literally `main` is still a lane",
      run(bash("git add .", cwd="/home/tom/code/north/worktrees/main")) is None)
check("a path under <project>/main IS protected",
      run(bash("git add x", cwd="/home/tom/code/north/main")))
check("`worktrees` is matched at container depth, not anywhere in the path",
      run({"tool_name": "Edit", "tool_input": {
          "file_path": "/home/tom/code/north/main/docs/worktrees/notes.md"}}))
check("unrelated repos are untouched",
      run(bash("git commit -m x", cwd="/home/tom/code/some-other-project")) is None)
check("a sibling like north-data must not match",
      run(bash("git add x", cwd="/home/tom/code/north-data")) is None)

# The CONTAINER root is not a checkout: it holds main/, worktrees/ and pins/,
# so a symlink or scratch file there cannot dirty anything. Denying it left no
# compliant way to place a compatibility symlink during the migration.
check("the container root itself is writable",
      run(bash("ln -s main/orchestration orchestration-probe",
               cwd="/home/tom/code/north")) is None)
check("but <project>/main is still protected",
      run(bash("touch x", cwd="/home/tom/code/north/main")) is not False)

print("--- Edit/Write behaviour is unchanged ---")

check("Edit into a primary is denied",
      run({"tool_name": "Edit",
           "tool_input": {"file_path": "/home/tom/code/north/main/cli/x.clj"}}))
check("Edit into a lane is allowed",
      run({"tool_name": "Edit",
           "tool_input": {
               "file_path": "/home/tom/code/north/worktrees/a/cli/x.clj"}}) is None)
check("Edit outside ~/code is allowed",
      run({"tool_name": "Edit", "tool_input": {"file_path": "/tmp/x.clj"}}) is None)

print("--- every container's main, not only the launch-critical ones ---")

# A fixture code root: dynamic detection must cover a project the guard has
# never heard of, and must not sweep in the near-misses that live beside one.
FIX = tempfile.mkdtemp(prefix="lc-guard-")
ROOT = os.path.join(FIX, "code")
PIN_OID = "0123456789abcdef0123456789abcdef01234567"
NEXT_PIN_OID = "89abcdef0123456789abcdef0123456789abcdef"
for rel in ("proj/main/.git", "proj/worktrees/x/.git", "proj/worktrees/main",
            f"proj/pins/{PIN_OID}", "client/msa/app/main/.git",
            "resources/upstream/main/.git", "runtime-data/.git", "plain-dir"):
    os.makedirs(os.path.join(ROOT, rel), exist_ok=True)
PIN = os.path.join(ROOT, "proj", "pins", PIN_OID)
PIN_SIDECAR = os.path.join(ROOT, "proj", "pins", PIN_OID + ".pin")
open(PIN_SIDECAR, "w").write(
    "vendored upstream checkout. Consumers: the docs build.\n")

PROJ = os.path.join(ROOT, "proj", "main")
CLIENT = os.path.join(ROOT, "client", "msa", "app", "main")


def fixture(command, cwd=None):
    return run(bash(command, cwd=cwd or ROOT), code_root=ROOT)


check("an unheard-of project's main is protected",
      fixture("git commit -m x", cwd=PROJ))
check("a client project's nested main is protected",
      fixture("git add .", cwd=CLIENT))
check("the deny names the nested container",
      "client/msa/app" in (fixture("git add .", cwd=CLIENT) or ""))
check("its lane is not",
      fixture("git commit -m x",
              cwd=os.path.join(ROOT, "proj", "worktrees", "x")) is None)
check("a lane whose slug is literally `main` is not the primary",
      fixture("git commit -m x",
              cwd=os.path.join(ROOT, "proj", "worktrees", "main")) is None)
check("a data dir with a bare .git and no main/ stays writable",
      fixture("git commit -m x", cwd=os.path.join(ROOT, "runtime-data")) is None)
check("a directory that is no checkout at all is untouched",
      fixture("rm -rf junk", cwd=os.path.join(ROOT, "plain-dir")) is None)
check("~/code/resources is read-only context, never this guard's business",
      fixture("cat notes.md",
              cwd=os.path.join(ROOT, "resources", "upstream", "main")) is None)
check("Edit into an unheard-of project's main is denied",
      run({"tool_name": "Edit",
           "tool_input": {"file_path": os.path.join(PROJ, "src/x.py")}},
          code_root=ROOT))
check("Edit into ~/code/resources is allowed",
      run({"tool_name": "Edit",
           "tool_input": {"file_path": os.path.join(
               ROOT, "resources/upstream/main/x.py")}},
          code_root=ROOT) is None)

print("--- pins/: protected because something OUTSIDE consumes them ---")

# A pin is not a main and not a lane. Its deny must carry its own noun, its
# own WHY, and its own remedy — replacement while live, verified retirement
# once orphaned. Answering a pin
# deny with "work in a worktree" sends the agent to break what is protected.
PIN_HIT = run({"tool_name": "Edit",
               "tool_input": {"file_path": os.path.join(PIN, "index.html")}},
              code_root=ROOT)
check("a write into a pin is denied", PIN_HIT)
check("the pin deny names the .pin manifest",
      f"pins/{PIN_OID}.pin" in (PIN_HIT or ""))
check("the pin deny names the manifest's consumers",
      "the docs build" in (PIN_HIT or ""))
check("the pin deny names new content-addressed pin creation",
      "worktree add --detach" in (PIN_HIT or ""))
check("the pin deny names verified orphan retirement",
      "pin-retire" in (PIN_HIT or ""))
check("the pin deny never names in-place checkout",
      "checkout REF" not in (PIN_HIT or ""))
check("the manifest is agent-writable pin METADATA (AMB-6 as amended)",
      run({"tool_name": "Edit",
           "tool_input": {"file_path": os.path.join(
               ROOT, "proj", "pins", PIN_OID + ".pin")}},
          code_root=ROOT) is None)
check("a .pin-named path INSIDE a pin checkout is still content, still denied",
      run({"tool_name": "Edit",
           "tool_input": {"file_path": os.path.join(PIN, "nested.pin")}},
          code_root=ROOT))
check("the pins/ ROOT itself stays writable — a container must grow one",
      fixture("mkdir -p site", cwd=os.path.join(ROOT, "proj", "pins")) is None)
check("the worktrees/ ROOT itself stays writable",
      fixture("mkdir -p lane",
              cwd=os.path.join(ROOT, "proj", "worktrees")) is None)
check("a redirect into a pin is denied",
      fixture(f"echo x > {os.path.join(PIN, 'x.txt')}"))
check("sed -i inside a pin is denied",
      fixture(f"sed -i s/a/b/ {os.path.join(PIN, 'x.txt')}"))
check("committing inside a pin is denied", fixture("git commit -am x", cwd=PIN))
check("quoted PROSE naming a pin git command is not an invocation",
      fixture("printf 'git -C " + PIN + " commit -am x' >> /tmp/pin-notes.txt")
      is None)
check("a semicolon inside quoted prose is not a command boundary",
      fixture("echo 'example; git -C " + PIN
              + " checkout deadbeef' >> /tmp/pin-notes.txt") is None)
check("an and-list inside quoted prose is not a command boundary",
      fixture("echo 'example && git -C " + PIN
              + " checkout deadbeef' >> /tmp/pin-notes.txt") is None)
check("a single-quoted command substitution remains literal prose",
      fixture("echo '$(git -C " + PIN
              + " checkout deadbeef)' >> /tmp/pin-notes.txt") is None)
check("the same command unquoted is still a live call, still denied",
      fixture("git -C " + PIN + " commit -am x"))
check("raw rm cannot erase a live pin sidecar",
      fixture(f"rm {PIN_SIDECAR}"))
check("raw unlink cannot erase a live pin sidecar",
      fixture(f"unlink {PIN_SIDECAR}"))
check("raw mv cannot rename a live pin sidecar",
      fixture(f"mv {PIN_SIDECAR} {PIN_SIDECAR}.bak"))
check("the verified pin retirement helper is allowed",
      fixture(f"pin-retire --consumer-main {PROJ} -- {PIN}") is None)
check("pin-retire cannot hide a command-substitution pin mutation",
      fixture(f"pin-retire --consumer-main {PROJ} -- "
              f"$(git -C {PIN} checkout deadbeef)"))
check("pin-retire cannot shield a later pin mutation",
      fixture(f"pin-retire --consumer-main {PROJ} -- {PIN}; "
              f"git -C {PIN} checkout deadbeef"))
check("checkout cannot change a content-addressed pin's HEAD",
      fixture(f"git -C {PIN} checkout 3e942ba2"))
check("a double-quoted -C path cannot hide pin checkout",
      fixture(f'git -C "{PIN}" checkout 3e942ba2'))
check("a single-quoted -C path cannot hide pin switch",
      fixture(f"git -C '{PIN}' switch --detach 3e942ba2"))
check("a parenthesized subshell cannot hide pin checkout",
      fixture(f"(git -C {PIN} checkout deadbeef)"))
check("a command substitution cannot hide pin checkout",
      fixture(f'echo "$(git -C {PIN} checkout deadbeef)"'))
check("a backtick substitution cannot hide pin checkout",
      fixture(f"echo `git -C {PIN} checkout deadbeef`"))
check("sh -c cannot hide pin checkout",
      fixture(f"sh -c 'git -C {PIN} checkout deadbeef'"))
check("bash -lc cannot hide pin checkout",
      fixture(f"bash -lc 'git -C {PIN} checkout deadbeef'"))
check("bash -ec cannot hide pin checkout",
      fixture(f"bash -ec 'git -C {PIN} checkout deadbeef'"))
check("sh -c -- cannot hide pin checkout",
      fixture(f"sh -c -- 'git -C {PIN} checkout deadbeef'"))
check("a shell name passed to echo is data, not an executable",
      fixture(f"echo sh -c 'git -C {PIN} checkout deadbeef'") is None)
check("switch --detach cannot change a content-addressed pin's HEAD",
      fixture(f"git -C {PIN} switch --detach 3e942ba2"))
check("a working-tree checkout in a pin is also denied",
      fixture(f"git -C {PIN} checkout -- ."))
check("creating a branch in a pin is denied",
      fixture(f"git -C {PIN} checkout -b mine"))
check("a checkout cannot shield a later write into the pin",
      fixture(f"git -C {PIN} checkout abc123 && "
              f"echo x > {os.path.join(PIN, 'x.txt')}"))
check("a replacement full-object-ID pin may be created from main",
      fixture(f"git -C {PROJ} worktree add --detach "
              f"{os.path.join(ROOT, 'proj', 'pins', NEXT_PIN_OID)} "
              f"{NEXT_PIN_OID}") is None)
check("an existing pin cannot be the source of worktree creation",
      fixture(f"git -C '{PIN}' worktree add --detach "
              f"{os.path.join(ROOT, 'proj', 'pins', NEXT_PIN_OID)} "
              f"{NEXT_PIN_OID}"))
check("worktree remove cannot delete an immutable pin",
      fixture(f"git -C {PROJ} worktree remove {PIN}"))
check("worktree move cannot rename an immutable pin",
      fixture(f"git -C {PROJ} worktree move {PIN} "
              f"{os.path.join(ROOT, 'proj', 'pins', NEXT_PIN_OID)}"))
check("worktree move remains available for an ordinary lane",
      fixture(f"git -C {PROJ} worktree move "
              f"{os.path.join(ROOT, 'proj', 'worktrees', 'x')} "
              f"{os.path.join(ROOT, 'proj', 'worktrees', 'y')}") is None)
check("an earlier lane commit cannot hide a later pin checkout",
      fixture(f"git -C {os.path.join(ROOT, 'proj', 'worktrees', 'x')} "
              f"commit -am x ; git -C \"{PIN}\" checkout deadbeef"))
check("an earlier lane commit cannot hide later pin removal",
      fixture(f"git -C {os.path.join(ROOT, 'proj', 'worktrees', 'x')} "
              f"commit -am x ; git -C {PROJ} worktree remove {PIN}"))
check("reading a pin is always fine",
      fixture(f"cat {os.path.join(PIN, 'index.html')}") is None)
check("a reset --hard in a pin denies with the PIN reason, not wt-rescue",
      "wt-rescue" not in (fixture(f"git -C {PIN} reset --hard") or "x"))

delete_sidecar = ENV.format(verb="Delete", path=PIN_SIDECAR, body="")
move_sidecar = ENV.format(
    verb="Update", path=PIN_SIDECAR,
    body=f"*** Move to: {PIN_SIDECAR}.bak\n@@\n-old\n+new\n")
update_sidecar = ENV.format(
    verb="Update", path=PIN_SIDECAR, body="@@\n-old\n+new\n")
check("apply_patch Delete File cannot erase a live pin sidecar",
      run(patch(delete_sidecar), code_root=ROOT))
check("apply_patch Move to cannot rename a live pin sidecar",
      run(patch(move_sidecar), code_root=ROOT))
check("apply_patch may update live pin consumer metadata",
      run(patch(update_sidecar), code_root=ROOT) is None)
mixed_move = (
    "*** Begin Patch\n"
    f"*** Update File: {PIN_SIDECAR}\n@@\n-old\n+new\n"
    f"*** Update File: {os.path.join(ROOT, 'proj', 'worktrees', 'x', 'move-me')}\n"
    f"*** Move to: {os.path.join(ROOT, 'proj', 'worktrees', 'x', 'moved')}\n"
    "@@\n-old\n+new\n"
    "*** End Patch")
check("an unrelated move does not turn a sidecar update into a removal",
      run(patch(mixed_move), code_root=ROOT) is None)

shutil.rmtree(FIX, ignore_errors=True)

print("--- destroying human WIP in a main checkout ---")

NIXOS = "/home/tom/code/nixos-config/main"

check("reset --hard against nixos-config/main (the 2026-07-30 near-miss)",
      run(bash("git -C /home/tom/code/nixos-config/main reset --hard HEAD~1")))
check("the deny names a compliant move",
      "status --porcelain" in (run(bash(f"git -C {NIXOS} reset --hard")) or ""))
check("reset --merge is the same loss", run(bash(f"git -C {NIXOS} reset --merge")))
check("stash from inside a main", run(bash("git stash", cwd=NIXOS)))
check("stash push with a message", run(bash("git stash push -m wip", cwd=NORTH)))
check("stash pop", run(bash("git stash pop", cwd=NORTH)))
check("checkout -- <path> discards the edit",
      run(bash("git checkout -- cli/x.clj", cwd=NORTH)))
check("restore of the working tree", run(bash("git restore cli/x.clj", cwd=NORTH)))
check("clean -fd", run(bash("git clean -fd", cwd=NORTH)))
check("clean -ffdx", run(bash(f"git -C {NIXOS} clean -ffdx")))

# The hole this class closes: the old scan stopped at the FIRST git call, so a
# sanctioned verb ahead of a destructive one vouched for the whole line.
check("a sanctioned verb earlier in the line does not shield a reset --hard",
      run(bash(f"git -C {NORTH} worktree add /tmp/lane-y -b y && "
               f"git -C {NORTH} reset --hard origin/main")))
check("...nor a stash after a fetch",
      run(bash(f"git -C {NORTH} fetch origin && git -C {NORTH} stash")))

check("git stash list is a read", run(bash("git stash list", cwd=NORTH)) is None)
check("git clean --dry-run is a read", run(bash("git clean -nd", cwd=NORTH)) is None)
# --staged spares the working tree, so it is not WIP destruction — but it still
# rewrites an index the human staged, so it stays denied as an ordinary mutation.
_staged = run(bash("git restore --staged cli/x.clj", cwd=NORTH))
check("git restore --staged is a mutation, not WIP destruction",
      _staged and "work-in-progress" not in _staged)

print("--- wt-rescue is the sanctioned remediation and must pass ---")

# It performs internally the cleanup denied raw. A guard that blocks the move
# its own deny message recommends leaves the lane trapped.
check("wt-rescue against a main is allowed",
      run(bash(f"wt-rescue {NIXOS}")) is None)
check("wt-rescue with no path, run from inside a main",
      run(bash("wt-rescue", cwd=NORTH)) is None)
check("wt-rescue --dry-run is allowed",
      run(bash(f"wt-rescue {NORTH} --dry-run")) is None)
check("the checkout-- denial names wt-rescue",
      "wt-rescue" in (run(bash(f"git -C {NIXOS} checkout -- .")) or ""))
check("the reset --hard denial names wt-rescue",
      "wt-rescue" in (run(bash(f"git -C {NIXOS} reset --hard")) or ""))
check("the denial names the deliberate-bypass escape",
      "north config agents off launch-critical-worktree-guard"
      in (run(bash("git stash", cwd=NORTH)) or ""))
check("the allowlist is per SEGMENT — a reset --hard after it still denies",
      run(bash(f"wt-rescue {NORTH} && git -C {NORTH} reset --hard origin/main")))
check("...and a plain mutation after it still denies",
      run(bash(f"wt-rescue {NORTH}; git -C {NORTH} commit -m x")))
# wt-rescue's destination moved with the layout: it now lands the human's
# dirty state in <container>/worktrees/rescue-<ts>. That tree must be
# writable, or the tool the deny message recommends produces a tree the
# guard then refuses.
check("a wt-rescue's own rescue tree is a lane under worktrees/",
      run(bash("git add .",
               cwd="/home/tom/code/north/worktrees/rescue-20260730-1600"))
      is None)
check("the word wt-rescue as mere text vouches for nothing",
      run(bash(f"echo wt-rescue && git -C {NORTH} reset --hard")))

check("reset --hard INSIDE a lane is the lane's own business",
      run(bash("git reset --hard origin/main",
               cwd="/home/tom/code/north/worktrees/abc")) is None)
check("stash inside a lane is fine",
      run(bash("git -C /home/tom/code/north/worktrees/abc stash")) is None)
check("clean -fd inside a lane is fine",
      run(bash("git clean -fd", cwd="/home/tom/code/beagle/worktrees/abc")) is None)

print("--- the landing flow must still run from main ---")

check("worktree remove", run(bash(
    "git -C /home/tom/code/north/main worktree remove "
    "/home/tom/code/north/worktrees/x")) is None)
check("worktree prune",
      run(bash("git -C /home/tom/code/north/main worktree prune")) is None)
check("branch -d", run(bash("git -C /home/tom/code/north/main branch -d slug")) is None)
check("branch -D", run(bash("git branch -D slug", cwd=NORTH)) is None)
check("safe-push", run(bash("safe-push --to main", cwd=NORTH)) is None)
check("git show", run(bash("git show --stat HEAD", cwd=NORTH)) is None)
check("the whole sequence in one command", run(bash(
    "git -C /home/tom/code/north/main merge --ff-only slug && "
    "git -C /home/tom/code/north/main branch -d slug && "
    "git -C /home/tom/code/north/main worktree prune")) is None)
check("rebase run in a LANE is untouched",
      run(bash("git rebase main",
               cwd="/home/tom/code/north/worktrees/abc")) is None)
check("rebase run in main is not",
      run(bash("git rebase origin/main", cwd=NORTH)))

print("--- apply_patch envelopes: every header form ---")

add_main = ENV.format(verb="Add", path=f"{NORTH}/cli/x.clj", body="+x\n")
update_relative = ENV.format(verb="Update", path="cli/x.clj", body="@@\n-a\n+b\n")
delete_beagle = ENV.format(verb="Delete", path=f"{BEAGLE}/x.rkt", body="")
move_main = ENV.format(
    verb="Update", path="/home/tom/code/north/worktrees/abc/a.clj",
    body=f"*** Move to: {NORTH}/a.clj\n@@\n-a\n+b\n")
move_lane = ENV.format(
    verb="Update", path="/home/tom/code/north/worktrees/abc/a.clj",
    body="*** Move to: /home/tom/code/north/worktrees/abc/b.clj\n@@\n-a\n+b\n")
tmp_add = ENV.format(verb="Add", path="/tmp/x.txt", body="+x\n")

check("Add File with an absolute primary target is denied", run(patch(add_main)))
check("Update File resolves a relative target against cwd",
      run(patch(update_relative, cwd=NORTH)))
check("Delete File into beagle's primary is denied", run(patch(delete_beagle)))
check("Move to destination alone trips primary protection", run(patch(move_main)))
check("Update and Move to within a lane are allowed",
      run(patch(move_lane)) is None)
check("Add File outside protected checkouts is allowed", run(patch(tmp_add)) is None)
check("a nested envelope is found recursively", run({
    "tool_name": "apply_patch",
    "tool_input": {"arguments": {"patch": add_main}},
    "cwd": "/home/tom",
}))
check("a prefixed functions.apply_patch tool is recognized",
      run(patch(add_main, tool="functions.apply_patch")))
check("an explicit file_path remains authoritative",
      run(patch(tmp_add, extra={"file_path": f"{NORTH}/cli/x.clj"})))
check("the apply_patch deny names the project",
      "north" in (run(patch(add_main)) or ""))
check("the apply_patch deny gives the worktree escape route",
      "worktree add" in (run(patch(add_main)) or ""))
malformed = "*** Begin Patch\n*** Frobnicate: x\n*** End Patch"
check("a malformed apply_patch envelope is denied", run(patch(malformed)))
check("the malformed-envelope deny is explicitly fail-closed",
      "fail-closed" in (run(patch(malformed)) or ""))
check("an apply_patch tool call without an envelope is denied",
      run(patch("no patch here")))
check("tool_input.workdir wins over payload cwd for relative targets",
      run(patch(update_relative, cwd="/tmp", extra={"workdir": NORTH})))
check("a relative target under /tmp is allowed",
      run(patch(ENV.format(verb="Update", path="x.txt", body="@@\n-a\n+b\n"),
                extra={"workdir": "/tmp"})) is None)

print("--- apply_patch through the shell ---")

protected_heredoc = (
    "apply_patch <<'EOF'\n" + add_main + "\nEOF")
lane_envelope = ENV.format(
    verb="Update", path="/home/tom/code/north/worktrees/abc/cli/x.clj",
    body="@@\n-a\n+b\n")
lane_heredoc = "apply_patch <<'EOF'\n" + lane_envelope + "\nEOF"
check("a shell apply_patch heredoc into a primary is denied",
      run(bash(protected_heredoc)))
check("a shell apply_patch heredoc into a lane is allowed",
      run(bash(lane_heredoc)) is None)
check("an envelope written as pure heredoc data is allowed", run(bash(
    "cat > /tmp/t.md <<'EOF'\n*** Begin Patch\n"
    f"*** Update File: {NORTH}/x\n*** End Patch\nEOF")) is None)
check("apply_patch input redirection fails closed",
      "fail-closed" in (run(bash("apply_patch < /tmp/patch.txt")) or ""))
check("the direct apply_patch argv form is denied", run(bash([
    "apply_patch", add_main,
])))
check("the direct apply_patch argv form allows a lane", run(bash([
    "apply_patch", lane_envelope,
])) is None)
check("an argv shell wrapper invoking apply_patch is denied", run(bash([
    "bash", "-lc", protected_heredoc,
])))
check("an allowed envelope cannot shield a later destructive git command",
      run(bash(lane_heredoc +
               f"\n&& git -C {NORTH} reset --hard")))
check("generic non-apply_patch argv handling remains out of scope",
      run(bash(["rm", f"{NORTH}/x"])) is None)

print("--- removing what git does not track ---")

# A real repo: the fixtures above only mkdir a .git, so git commands there fail
# and the exemption correctly stays closed.
REPO_ROOT = os.path.join(FIX, "code2")
REPO = os.path.join(REPO_ROOT, "proj", "main")
os.makedirs(os.path.join(REPO, "src"), exist_ok=True)
os.makedirs(os.path.join(REPO, "build"), exist_ok=True)
open(os.path.join(REPO, "src", "kept.txt"), "w").write("tracked\n")
open(os.path.join(REPO, "build", "out.js"), "w").write("generated\n")
_q = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
subprocess.run(["git", "init", "-q", REPO], **_q)
subprocess.run(["git", "-C", REPO, "add", "src/kept.txt"], **_q)
subprocess.run(["git", "-C", REPO, "-c", "user.email=t@x", "-c", "user.name=t",
                "commit", "-qm", "seed"], **_q)


def repo_fixture(command):
    return run(bash(command, cwd=REPO_ROOT), code_root=REPO_ROOT)


check("rm of an untracked directory is allowed — it is not part of the tree",
      repo_fixture(f"rm -rf {os.path.join(REPO, 'build')}") is None)
check("rm of a tracked file is still denied",
      repo_fixture(f"rm {os.path.join(REPO, 'src', 'kept.txt')}"))
check("rm of a directory holding tracked files is still denied",
      repo_fixture(f"rm -rf {os.path.join(REPO, 'src')}"))
check("rm of the whole main checkout is still denied",
      repo_fixture(f"rm -rf {REPO}"))
check("the exemption is for removal only — writing a new file still denied",
      repo_fixture(f"echo x > {os.path.join(REPO, 'build', 'new.js')}"))

print("--- package-manager subcommands are not write commands ---")

check("bun install in a main checkout is allowed",
      repo_fixture(f"cd {REPO} && bun install") is None)
check("npm install is allowed", repo_fixture(f"cd {REPO} && npm install") is None)
check("cargo install is allowed", repo_fixture(f"cd {REPO} && cargo install x") is None)
check("a real install(1) into a main checkout is still denied",
      repo_fixture(f"install -m 644 /tmp/x {os.path.join(REPO, 'src', 'x')}"))
check("a package manager cannot shield a later destructive command",
      repo_fixture(f"bun install && rm {os.path.join(REPO, 'src', 'kept.txt')}"))

print("--- shell redirections are not arguments ---")

check("rm of an untracked path with 2>/dev/null is still allowed",
      repo_fixture(f"rm -rf {os.path.join(REPO, 'build')} 2>/dev/null") is None)
check("a redirection does not become an rm target",
      repo_fixture(f"rm -rf /tmp/elsewhere 2>/dev/null") is None)
check("rm of a tracked file is still denied with a redirection attached",
      repo_fixture(f"rm {os.path.join(REPO, 'src', 'kept.txt')} 2>/dev/null"))
check("a real redirect INTO a main checkout is still denied",
      repo_fixture(f"echo hi > {os.path.join(REPO, 'src', 'new.txt')}"))

print("--- fail-open ---")

check("no command field is allowed", run({"tool_name": "Bash", "tool_input": {}}) is None)
check("empty payload is allowed", run({}) is None)
check("unparseable command does not crash",
      run(bash('git add "unclosed', cwd=NORTH)) is not False)

print()
if failures:
    print(f"launch-critical guard: {len(failures)} FAILED of {checks}")
    sys.exit(1)
print(f"launch-critical guard: {checks} / {checks} PASS")
