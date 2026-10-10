import fcntl
import json
import os
import shlex
import subprocess
import sys
import time
import tomllib
import uuid
from pathlib import Path

VERSION = 1
BUDGETS = {"proxy": 3, "lead": 2, "sub-lead": 1, "worker": 0}
STATES = ("active", "finished")
PROXY = {"id": "proxy", "role": "proxy", "domain": "all", "provider": "claude",
         "session": "Tom's top-level claude", "depth": 0, "budget": BUDGETS["proxy"], "state": "active"}
CLAUDE_LEAD = ["--model", "claude-opus-5-5", "--effort", "high", "--permission-mode", "bypassPermissions"]
FIELDS = {"role", "domain", "parent", "provider", "session", "brief", "status", "budget", "depth", "pid", "state"}
USAGE = """usage: agents org [show]
       agents org add NAME --role ROLE --domain DOMAIN [--parent NAME] [--provider claude|codex]
                      [--session ID] [--brief FILE] [--status FILE] [--budget N] [--depth N] [--pid N]
       agents org set NAME [--state active|finished] [--session ID] [--status FILE] [--budget N] [--pid N]
       agents org finish NAME     mark the workstream finished; the launcher deregisters it on exit
       agents org exit NAME       launcher exit hook: remove a finished node, flag an active one as died
       agents org remove NAME     remove the node and its subtree
       agents org priority         print Tom's project priority order from orchestration.toml
       agents lead start --provider claude|codex --domain DOMAIN --brief FILE [--name NAME]
                      [--role lead|sub-lead] [--parent NAME] [--budget N] [--cwd DIR] [-- PROVIDER ARGS]
       agents lead restart NAME   reopen a lead that died while active, from its brief and status file
The chain of command lives in $AGENTS_ORG_FILE (default ~/.local/state/agents/org.json,
schema dotfiles/agents/org.schema.json); the proxy,
Tom's top-level session, is always the root. Default delegation budgets: proxy 3, lead 2,
sub-lead 1, worker 0. lead start registers the node, opens the session without taking focus with
AGENT_ROLE, AGENT_DEPTH, AGENT_DELEGATION_BUDGET and AGENT_ORG_NAME set, and runs `org exit` when
the session ends."""


def die(msg, code=2):
    print(f"agents org: {msg}", file=sys.stderr)
    sys.exit(code)


def org_file():
    return os.environ.get("AGENTS_ORG_FILE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "agents", "org.json")


def priority():
    path = os.environ.get("AGENTS_ORCHESTRATION") or Path(__file__).resolve().parent.parent / "orchestration.toml"
    try:
        with open(path, "rb") as f:
            projects = tomllib.load(f).get("projects", {})
        order = sorted(projects, key=lambda name: projects[name].get("priority", float("inf")))
    except (OSError, ValueError, TypeError, AttributeError) as e:
        die(f"cannot read project priority from {path}: {e}")
    return "priority: " + (" > ".join(order) or "unset ([projects] in orchestration.toml)")


class Org:
    def __enter__(self):
        path = org_file()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.lock = open(path + ".lock", "w")
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except FileNotFoundError:
            data = {"version": VERSION}
        except (OSError, ValueError) as e:
            die(f"cannot read {path}: {e}")
        if data.get("version") != VERSION:
            die(f"{path} has schema version {data.get('version')!r}; this tool reads version {VERSION}")
        self.data = data
        self.nodes = data.get("nodes", [])
        return self

    def save(self):
        path = org_file()
        tmp = f"{path}.{os.getpid()}.tmp"
        self.data["nodes"] = self.nodes
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=1)
            f.write("\n")
        os.replace(tmp, path)

    def __exit__(self, *_):
        self.lock.close()

    def find(self, name):
        if name == "proxy":
            return PROXY
        return next((n for n in self.nodes if n["id"] == name), None)

    def need(self, name):
        node = self.find(name)
        if node is None or node is PROXY:
            die(f"no registered node {name!r}; see agents org show")
        return node


def short(path):
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if path and path.startswith(home + "/") else path


def parse_opts(args, keys):
    opts, rest = {}, []
    while args:
        a = args.pop(0)
        if a == "--":
            rest.extend(args)
            break
        if a.startswith("--") and a[2:] in keys:
            if not args:
                die(f"{a} needs a value")
            opts[a[2:]] = args.pop(0)
        elif a.startswith("--"):
            die(f"unknown option {a}\n{USAGE}")
        else:
            rest.append(a)
    return opts, rest


def as_int(value, what):
    try:
        n = int(value)
    except (TypeError, ValueError):
        die(f"{what} must be an integer, got {value!r}")
    if n < 0:
        die(f"{what} must be at least 0")
    return n


def path_of(value):
    return os.path.abspath(os.path.expanduser(value)) if value else ""


def apply(node, opts):
    for key, value in opts.items():
        if key in ("budget", "depth", "pid"):
            node[key] = as_int(value, f"--{key}")
        elif key in ("brief", "status"):
            node["brief" if key == "brief" else "status_file"] = path_of(value)
        elif key == "state":
            if value not in STATES:
                die(f"--state must be one of {', '.join(STATES)}")
            node[key] = value
            node.pop("died", None)
        else:
            node[key] = value


def add(org, name, opts):
    role = opts.get("role")
    if role not in BUDGETS or role == "proxy":
        die(f"--role must be one of lead, sub-lead, worker, got {role!r}")
    if name == "proxy" or not name or any(c.isspace() for c in name):
        die(f"invalid node name {name!r}")
    up = org.find(opts.get("parent", "proxy"))
    if up is None:
        die(f"unknown parent {opts.get('parent')!r}; see agents org show")
    node = {"id": name, "role": role, "domain": "", "parent": up["id"], "provider": "claude",
            "session": "", "brief": "", "status_file": "", "depth": up["depth"] + 1, "budget": BUDGETS[role],
            "state": "active", "started": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    apply(node, {k: v for k, v in opts.items() if k != "parent"})
    if node["budget"] >= up["budget"]:
        die(f"{up['id']} has delegation budget {up['budget']}, so {name} can hold at most "
            f"{up['budget'] - 1}" if up["budget"] else f"{up['id']} has delegation budget 0 and cannot delegate")
    org.nodes = [n for n in org.nodes if n["id"] != name] + [node]
    org.save()
    return node


def remove(org, name):
    gone, frontier = set(), {name}
    while frontier:
        gone |= frontier
        frontier = {n["id"] for n in org.nodes if n.get("parent") in frontier} - gone
    before = len(org.nodes)
    org.nodes = [n for n in org.nodes if n["id"] not in gone]
    org.save()
    return before - len(org.nodes)


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except OSError:
        return True
    return True


def health(n):
    if n.get("state") == "finished":
        return "finished"
    if n.get("died") or (n.get("pid") and not alive(n["pid"])):
        return f"DIED while active, restart: agents lead restart {n['id']}"
    return "active"


def line(n):
    where = f"{n['provider']}:{n['session']}" if n.get("session") else n["provider"]
    out = (f"{n['id']}  {n['role']} · {n.get('domain') or '-'} · {where} · {health(n)}"
           f" · depth {n['depth']} · budget {n['budget']}")
    for key, label in (("brief", "brief"), ("status_file", "status")):
        if n.get(key):
            out += f" · {label} {short(n[key])}"
    return out


def show(org):
    print(priority())
    names = {n["id"] for n in org.nodes}
    kids = {}
    for n in org.nodes:
        parent = n.get("parent") if n.get("parent") in names else "proxy"
        kids.setdefault(parent, []).append(n)

    def walk(node, prefix, last, top):
        print(line(node) if top else prefix + ("└─ " if last else "├─ ") + line(node))
        below = kids.get(node["id"], [])
        for i, child in enumerate(below):
            walk(child, "" if top else prefix + ("   " if last else "│  "), i == len(below) - 1, False)

    walk(PROXY, "", True, True)


def launch(node, extra, cwd, resume=False):
    """Open the node's session without focus; returns the session id or None."""
    # Claude fast mode bills usage credits even with plan usage left (code.claude.com/docs/en/fast-mode).
    env = dict(os.environ, AGENT_ROLE=node["role"], AGENT_DEPTH=str(node["depth"]),
               AGENT_DELEGATION_BUDGET=str(node["budget"]), AGENT_ORG_NAME=node["id"], AGENT_DOMAIN=node["domain"], CLAUDE_CODE_DISABLE_FAST_MODE="1")
    prompt = f"Read {node['brief']} and follow it."
    if resume and node.get("status_file"):
        prompt += f" You were restarted after an unexpected exit; resume from {node['status_file']}."
    if node["provider"] == "codex":
        result = subprocess.run(["codex-lead", "start", node["brief"], *extra], env=dict(env, CODEX_LEAD_PROMPT=prompt), cwd=cwd,
                                stdout=subprocess.PIPE, text=True)
        out = result.stdout.strip().splitlines()
        return out[-1] if result.returncode == 0 and out else None
    session = str(uuid.uuid4())
    inner = shlex.join(["claude", "--session-id", session, *CLAUDE_LEAD, *extra, prompt])
    script = ('agents org set "$AGENT_ORG_NAME" --pid $$ >/dev/null; '
              f'trap \'agents org exit "$AGENT_ORG_NAME" >/dev/null\' EXIT HUP TERM; {inner}; exit $?')
    result = subprocess.run(["spawn-quiet", "ghostty", f"--title={node['id']}", f"--working-directory={cwd}",
                             "-e", "bash", "-c", script], env=env, cwd=cwd, stdout=subprocess.DEVNULL)
    return session if result.returncode == 0 else None


def lead_start(args):
    opts, extra = parse_opts(args, {"provider", "domain", "brief", "name", "parent", "budget", "cwd", "role"})
    provider = opts.get("provider", "claude")
    if provider not in ("claude", "codex"):
        die("--provider must be claude or codex")
    if "domain" not in opts or "brief" not in opts:
        die(f"lead start needs --domain and --brief\n{USAGE}")
    brief = os.path.realpath(os.path.expanduser(opts["brief"]))
    if not os.path.isfile(brief):
        die(f"brief not found: {opts['brief']}")
    name = opts.get("name") or f"{opts['domain']}-{'lead' if provider == 'claude' else 'codex-lead'}"
    cwd = os.path.expanduser(opts.get("cwd", os.getcwd()))
    node_opts = {"role": opts.get("role", "lead"), "domain": opts["domain"], "provider": provider, "brief": brief,
                 "status": os.path.splitext(brief)[0].removesuffix("-brief") + "-status.md",
                 "parent": opts.get("parent", os.environ.get("AGENT_ORG_NAME") or "proxy")}
    if "budget" in opts:
        node_opts["budget"] = opts["budget"]
    with Org() as org:
        if org.find(name) is not None:
            die(f"{name} is already in the org; agents org remove {name} first")
        node = add(org, name, node_opts)
        node["cwd"] = cwd
        node["args"] = extra
        org.save()
    started(name, launch(node, extra, cwd))


def lead_restart(args):
    if len(args) != 1:
        die(USAGE)
    with Org() as org:
        node = org.need(args[0])
        if health(node) == "active":
            die(f"{node['id']} is alive and active; nothing to restart")
        if node.get("state") == "finished":
            die(f"{node['id']} finished its workstream; start a new lead for new work")
        if not os.path.isfile(node.get("brief") or ""):
            die(f"{node['id']} has no readable brief to restart from: {node.get('brief') or 'none'}")
        node.pop("died", None)
        node.pop("pid", None)
        org.save()
    started(node["id"], launch(node, node.get("args", []), node.get("cwd") or os.getcwd(), resume=True))


def started(name, session):
    with Org() as org:
        node = org.need(name)
        if session is None:
            node["died"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            org.save()
            die(f"{name} failed to start", 1)
        node["session"] = session
        org.save()
        print(line(node))


def main(argv):
    help_args = argv[:argv.index("--")] if argv[:2] == ["lead", "start"] and "--" in argv else argv
    if any(arg in ("-h", "--help") for arg in help_args):
        print(USAGE)
        return
    if argv[:1] == ["lead"]:
        sub = argv[1:2]
        if sub == ["start"]:
            return lead_start(argv[2:])
        if sub == ["restart"]:
            return lead_restart(argv[2:])
        die(USAGE)
    args = argv[1:] if argv[:1] == ["org"] else list(argv)
    cmd = args.pop(0) if args else "show"
    if cmd in ("-h", "--help", "help"):
        print(USAGE)
        return
    if cmd == "priority":
        if args:
            die(USAGE)
        print(priority())
        return
    with Org() as org:
        if cmd == "show" and not args:
            show(org)
        elif cmd in ("add", "set"):
            opts, rest = parse_opts(args, FIELDS)
            if len(rest) != 1:
                die(USAGE)
            if cmd == "add":
                if "domain" not in opts:
                    die("add needs --role and --domain")
                node = add(org, rest[0], opts)
            else:
                node = org.need(rest[0])
                apply(node, opts)
                org.save()
            print(line(node))
        elif cmd == "finish" and len(args) == 1:
            node = org.need(args[0])
            node["state"] = "finished"
            org.save()
            print(line(node))
        elif cmd == "exit" and len(args) == 1:
            node = org.find(args[0])
            if node is None or node is PROXY:
                return
            if node.get("state") == "finished":
                remove(org, node["id"])
            else:
                node["died"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
                org.save()
        elif cmd == "remove" and len(args) == 1:
            print(f"removed {remove(org, args[0])} node(s)")
        else:
            die(USAGE)


if __name__ == "__main__":
    main(sys.argv[1:])
