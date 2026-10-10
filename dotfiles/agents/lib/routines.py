import datetime
import json
import os
import re
import subprocess
import sys

KINDS = ("session-cron", "systemd-timer", "cloud-routine")
FIELDS = ("name", "kind", "schedule", "owner", "purpose", "relates-to", "expires")
POINTER = re.compile(r"\[routine:([a-z0-9][a-z0-9-]*)\]")
USAGE = (
    "usage: agents routines [list] [--no-live] [--crons FILE|-]\n"
    "       agents routines show NAME\n"
    "       agents routines pointer NAME\n"
    "Lists dotfiles/agents/routines/*.md, compares them with live user timers and, given\n"
    "CronList output (--crons), with session crons; exits 1 on an unregistered live job,\n"
    "an expired or invalid entry."
)


def routines_dir():
    env = os.environ.get("AGENT_ROUTINES_DIR")
    if env:
        return env
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "routines")


def parse(path):
    text = open(path, encoding="utf-8").read()
    match = re.match(r"---\n(.*?)\n---\n(.*)\Z", text, re.S)
    if not match:
        return None, "no front matter"
    meta = {}
    for line in match.group(1).splitlines():
        key, sep, value = line.partition(":")
        if sep:
            meta[key.strip()] = value.strip()
    body = match.group(2).strip()
    meta["relates-to"] = [
        item.strip() for item in meta.get("relates-to", "").strip("[]").split(",") if item.strip()
    ]
    meta["body"] = body
    stem = os.path.splitext(os.path.basename(path))[0]
    missing = [f for f in FIELDS if not meta.get(f)]
    if missing:
        return meta, "missing " + ", ".join(missing)
    if meta["name"] != stem:
        return meta, f"name {meta['name']!r} differs from file {stem!r}"
    if meta["kind"] not in KINDS:
        return meta, f"kind {meta['kind']!r} is not one of {', '.join(KINDS)}"
    if meta["expires"] != "never":
        try:
            datetime.date.fromisoformat(meta["expires"])
        except ValueError:
            return meta, f"expires {meta['expires']!r} is neither never nor YYYY-MM-DD"
    if not body:
        return meta, "empty prompt or command"
    return meta, None


def load():
    root = routines_dir()
    entries, problems = {}, []
    for name in sorted(os.listdir(root)):
        if not name.endswith(".md"):
            continue
        meta, error = parse(os.path.join(root, name))
        if error:
            problems.append(f"INVALID {name}: {error}")
            continue
        entries[meta["name"]] = meta
    return entries, problems


def pointer(name):
    return f"[routine:{name}] Run `agents routines show {name}` and follow it."


def live_timers():
    try:
        listed = subprocess.run(
            ["systemctl", "--user", "list-timers", "--all", "--output=json", "--no-pager"],
            capture_output=True, text=True, timeout=20, check=True,
        ).stdout
        units = [row["unit"] for row in json.loads(listed)]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        return None
    if not units:
        return []
    shown = subprocess.run(
        ["systemctl", "--user", "show", "-p", "Id", "-p", "FragmentPath", *units],
        capture_output=True, text=True, timeout=20,
    ).stdout
    own = os.path.join(os.path.expanduser("~"), ".config/systemd/user") + "/"
    timers = []
    for block in shown.strip().split("\n\n"):
        props = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if props.get("FragmentPath", "").startswith(own):
            timers.append(props["Id"].removesuffix(".timer"))
    return timers


def cmd_list(args):
    live, crons = True, None
    while args:
        arg = args.pop(0)
        if arg == "--no-live":
            live = False
        elif arg == "--crons" and args:
            source = args.pop(0)
            crons = sys.stdin.read() if source == "-" else open(source, encoding="utf-8").read()
        else:
            print(USAGE, file=sys.stderr)
            return 2
    entries, problems = load()
    today = datetime.date.today()
    print(f"{'NAME':24} {'KIND':14} {'SCHEDULE':34} OWNER")
    for meta in entries.values():
        print(f"{meta['name']:24} {meta['kind']:14} {meta['schedule'][:34]:34} {meta['owner']}")
        if meta["expires"] != "never" and datetime.date.fromisoformat(meta["expires"]) < today:
            problems.append(f"EXPIRED {meta['name']}: expired {meta['expires']}")
    if live:
        timers = live_timers()
        if timers is None:
            print("live timers: systemctl --user unavailable")
        else:
            registered = {n for n, m in entries.items() if m["kind"] == "systemd-timer"}
            print(f"live timers: {len(timers)} ({len(set(timers) & registered)} registered)")
            for unit in timers:
                if unit not in registered:
                    problems.append(f"UNREGISTERED systemd-timer {unit}: add dotfiles/agents/routines/{unit}.md")
            for name in sorted(registered - set(timers)):
                print(f"not live: {name}")
    if crons is not None:
        sessions = {n for n, m in entries.items() if m["kind"] == "session-cron"}
        count = 0
        for line in crons.splitlines():
            if not line.strip():
                continue
            count += 1
            found = POINTER.search(line)
            if not found:
                problems.append(f"UNREGISTERED session-cron: {line.strip()[:100]}")
            elif found.group(1) not in sessions:
                problems.append(f"UNREGISTERED session-cron [routine:{found.group(1)}]: no such session-cron entry")
        print(f"session crons: {count} checked")
    for problem in problems:
        print(problem)
    print(f"routines: {len(entries)} entries, {len(problems)} problem(s)")
    return 1 if problems else 0


def main(argv):
    command = argv.pop(0) if argv and not argv[0].startswith("-") else "list"
    if command == "list":
        return cmd_list(argv)
    if command in ("show", "pointer") and len(argv) == 1:
        entries, _ = load()
        meta = entries.get(argv[0])
        if meta is None:
            print(f"agents routines: no valid entry named {argv[0]!r}", file=sys.stderr)
            return 1
        if command == "pointer":
            print(pointer(meta["name"]))
        else:
            print(f"# routine {meta['name']} ({meta['kind']}, {meta['schedule']}): {meta['purpose']}")
            print(meta["body"])
        return 0
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
