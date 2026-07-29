#!/usr/bin/env python3
"""The guard must refuse the Bash calls that actually breached the primaries.

Every DENY case below is a verbatim command shape an agent ran against a
launch-critical primary on 2026-07-29 while the guard was live and wired. None
of them fired, because the guard only inspected `tool_input.file_path`, which a
Bash call does not have. These cases exist so that hole cannot reopen.

The ALLOW cases matter just as much: a guard that also blocks reads, or blocks
`git worktree add` — the very escape route its deny message recommends — traps
the agent with no compliant move, and the next person turns the guard off.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DECIDE = os.path.join(HERE, "lib", "launch_critical_decide.py")

failures = []
checks = 0


def run(payload):
    p = subprocess.run([sys.executable, DECIDE], input=json.dumps(payload),
                       capture_output=True, text=True, timeout=30)
    out = p.stdout.strip()
    if not out:
        return None
    return json.loads(out)["hookSpecificOutput"]["permissionDecisionReason"]


def bash(command, cwd="/home/tom"):
    return {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd}


def check(label, condition):
    global checks
    checks += 1
    if condition:
        print("  PASS ", label)
    else:
        failures.append(label)
        print("  FAIL ", label)


NORTH = "/home/tom/code/north/main"
FRAM = "/home/tom/code/fram/main"

print("--- must DENY: what actually happened on 2026-07-29 ---")

check("heredoc patch with cwd in the north primary",
      run(bash("python3 - <<'PYEOF'\nopen('cli/deployed-cli.clj','w')\nPYEOF", cwd=NORTH)))

check("git add from inside the north primary",
      run(bash("git add cli/deployed-cli.clj", cwd=NORTH)))

check("git commit from inside the north primary",
      run(bash("git commit -q -m 'x'", cwd=NORTH)))

check("git reset --hard against the fram primary via -C",
      run(bash("git -C /home/tom/code/fram/main reset --hard origin/main")))

check("git add of many paths from inside the fram primary",
      run(bash("FILES=$(cat list); git add $FILES", cwd=FRAM)))

check("git push from inside the primary",
      run(bash("git push origin main", cwd=NORTH)))

check("redirection into a primary file",
      run(bash("echo x > /home/tom/code/north/main/cli/x.clj")))

check("sed -i against a primary file",
      run(bash("sed -i s/a/b/ /home/tom/code/fram/main/coord_daemon.clj")))

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
check("git diff against a primary", run(bash("git -C /home/tom/code/fram/main diff --stat")) is None)
check("grep inside a primary", run(bash("grep -rn foo cli/", cwd=NORTH)) is None)
check("cat a primary file", run(bash("cat /home/tom/code/north/main/cli/coord.clj")) is None)

check("git worktree add FROM the primary is the escape route, never blocked",
      run(bash("git -C /home/tom/code/north/main worktree add /home/tom/code/north/wt-x -b x")) is None)
check("git fetch INTO the primary is allowed",
      run(bash("git -C /home/tom/code/north/main fetch /home/tom/code/north/wt-x x:refs/heads/main")) is None)

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
      run(bash("cat > /tmp/t.sh <<'EOF'\nsed -i s/a/b/ /home/tom/code/fram/main/coord_daemon.clj\nEOF")) is None)

# ...while the real forms are still refused.
check("a REAL redirect into a primary is still denied",
      run(bash("echo x > /home/tom/code/north/main/cli/zz.clj")))
check("a REAL sed -i on a primary is still denied",
      run(bash("sed -i s/a/b/ /home/tom/code/fram/main/coord_daemon.clj")))

check("redirect to /tmp while cwd is a primary is fine",
      run(bash("grep foo cli/x.clj > /tmp/out", cwd=NORTH)) is None)

print("--- the wt-* carve-out (both layouts) ---")

check("writing in a wt- worktree is allowed",
      run(bash("git add .", cwd="/home/tom/code/north/wt-abc")) is None)
check("heredoc in a wt- worktree is allowed",
      run(bash("python3 - <<'EOF'\npass\nEOF", cwd="/home/tom/code/north/wt-abc")) is None)
check("a path under <project>/main IS protected (target layout)",
      run(bash("git add x", cwd="/home/tom/code/north/main")))
check("unrelated repos are untouched",
      run(bash("git commit -m x", cwd="/home/tom/code/some-other-project")) is None)
check("a sibling like north-data must not match",
      run(bash("git add x", cwd="/home/tom/code/north-data")) is None)

# The CONTAINER root is not a checkout: it holds only main/ and wt-*/, so a
# symlink or scratch file there cannot dirty anything. Denying it left no
# compliant way to place a compatibility symlink during the migration.
check("the container root itself is writable",
      run(bash("ln -s main/orchestration orchestration", cwd="/home/tom/code/north")) is None)
check("but <project>/main is still protected",
      run(bash("touch x", cwd="/home/tom/code/north/main")) is not False)

print("--- Edit/Write behaviour is unchanged ---")

check("Edit into a primary is denied",
      run({"tool_name": "Edit",
           "tool_input": {"file_path": "/home/tom/code/north/main/cli/x.clj"}}))
check("Edit into a wt- worktree is allowed",
      run({"tool_name": "Edit",
           "tool_input": {"file_path": "/home/tom/code/north/wt-a/cli/x.clj"}}) is None)
check("Edit outside ~/code is allowed",
      run({"tool_name": "Edit", "tool_input": {"file_path": "/tmp/x.clj"}}) is None)

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
