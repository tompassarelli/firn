{
  pkgs,
  design ? "agent-owned",
}:

let
  origin = "/srv/origin/proj.git";
  relative = "code/proj/main";
  operatorCheckout = "/home/operator/${relative}";
  checkoutOf =
    {
      agent-owned = "\"$HOME/$1\"";
      operator-checkout = operatorCheckout;
    }
    .${design};
  remote = pkgs.writeShellScript "offloaded-check" ''
    set -eu
    repo=${checkoutOf} base=$2 head=$3 name=$4 branch=$5 ref=refs/land-offload/$4
    root=$HOME/.cache/land-offload
    mkdir -p "$root"
    bundle=$(mktemp "$root/$name.bundle.XXXXXX")
    trap 'rm -f "$bundle"; git -C "$repo" update-ref -d "$ref" 2>/dev/null || true' EXIT
    cat >"$bundle"
    if ! git -C "$repo" bundle verify -q "$bundle"; then
      git -C "$repo" fetch -q --no-auto-maintenance origin || true
      git -C "$repo" bundle verify -q "$bundle" || { echo "offload: $repo lacks the commits under $base" >&2; exit 97; }
    fi
    git -C "$repo" fetch -q --no-auto-maintenance "$bundle" "+refs/heads/$branch:$ref"
    slot=$root/$name
    if [ -e "$slot/.git" ]; then git -C "$slot" checkout -q --detach -f "$head"; else git -C "$repo" worktree add -q --detach "$slot" "$head"; fi
    cd "$slot"
    sh ./check.sh
  '';
  bundleFor = pkgs.writeShellScript "lane-bundle" ''
    set -eu
    cd ${operatorCheckout}
    git bundle create -q - refs/heads/"$1" "^$2"
  '';
in
pkgs.testers.runNixOSTest {
  name = "agent-offload-${design}";

  nodes.host =
    { lib, ... }:
    {
      imports = [ ./default.nix ];
      options.myConfig.modules.users.username = lib.mkOption { type = lib.types.str; };
      config = {
        myConfig.modules.users.username = "operator";
        myConfig.modules.agent-user = {
          enable = true;
          gid = 1500;
        };
        users.users.operator = {
          isNormalUser = true;
          uid = 1000;
          homeMode = "0700";
        };
        environment.systemPackages = [ pkgs.git ];
        programs.git = {
          enable = true;
          config = {
            user = {
              name = "fixture";
              email = "fixture@example.invalid";
            };
            safe.directory = origin;
          };
        };
      };
    };

  testScript = ''
    import shlex

    checkout = "${operatorCheckout}"


    def operator(command):
        return host.succeed(f"runuser -l operator -c {shlex.quote(command)}").strip()


    def agent(command):
        return host.succeed(f"runuser -l agent -c {shlex.quote(command)}").strip()


    def offload(branch, base, head):
        bundle = f"runuser -l operator -c {shlex.quote(f'${bundleFor} {branch} {base}')}"
        check = f"runuser -l agent -c {shlex.quote(f'${remote} ${relative} {base} {head} proj-lane {branch}')}"
        status, output = host.execute(f"{bundle} | {check} 2>&1")
        print(f"the offloaded check of {branch} exited {status}:\n{output}")
        ran = dict(line.split(" ", 1) for line in output.splitlines() if line.startswith(("uid ", "dir ")))
        return status, output, ran


    def operator_state():
        return operator(
            f"cd {checkout} && git rev-parse HEAD && git --no-optional-locks status --porcelain"
            f" && find {checkout} -printf '%p %T@ %m %u\\n' | sort"
        )


    host.start()
    host.wait_for_unit("multi-user.target")
    agent_uid = host.succeed("id -u agent").strip()

    host.succeed("install -d -o operator -g users -m 0755 /srv/origin ${origin}")
    operator(f"git init -q --bare -b main ${origin} && mkdir -p {checkout} && chmod 0700 ~/code ~/code/proj {checkout}")
    operator(
        f"cd {checkout} && git init -q -b main && git remote add origin ${origin}"
        " && printf 'echo uid $(id -u)\\necho dir $(pwd)\\ntest \"$(cat answer)\" = 42\\n' > check.sh && echo 40 > answer"
        " && git add -A && git commit -q -m old && git push -q origin main"
    )
    agent("mkdir -p ~/code/proj && git clone -q ${origin} ~/${relative}")
    operator(
        f"cd {checkout} && echo 41 > answer && git commit -q -am base && git push -q origin main"
        " && git checkout -q -b lane && echo 42 > answer && git commit -q -am lane"
        " && git checkout -q -b next && echo next > note && git add note && git commit -q -m next"
        " && git checkout -q main"
    )
    base = operator(f"git -C {checkout} rev-parse main")
    lane = operator(f"git -C {checkout} rev-parse lane")
    following = operator(f"git -C {checkout} rev-parse next")
    host.succeed("test \"$(stat -c '%a' /home/operator)\" = 700", f"test \"$(stat -c '%a' {checkout})\" = 700")
    host.fail(f"runuser -l agent -c 'git -C ~/${relative} cat-file -e {base}'")
    before = operator_state()

    host.fail(
        "runuser -l agent -c 'ls /home/operator'",
        f"runuser -l agent -c 'cat {checkout}/check.sh'",
        f"runuser -l agent -c 'git -C {checkout} cat-file -e {base}'",
    )

    status, output, ran = offload("lane", base, lane)
    assert status == 0, f"the offloaded check of a lane failed as the agent:\n{output}"
    assert ran.get("uid") == agent_uid, f"the check ran as uid {ran.get('uid')}, not the agent's {agent_uid}"
    assert ran.get("dir", "").startswith("/home/agent/"), f"the check ran in {ran.get('dir')}, outside the agent's home"

    status, output, ran = offload("next", lane, following)
    assert status == 0, f"the agent's object store kept no commit of the lane it was shipped:\n{output}"
    assert ran.get("uid") == agent_uid, f"the next check ran as uid {ran.get('uid')}"

    host.succeed(
        "test \"$(stat -c '%U %a' /home/agent)\" = 'agent 700'",
        "test \"$(stat -c %U /home/agent/${relative}/.git/objects)\" = agent",
        "test -z \"$(find /home/agent -not -user agent -print)\"",
    )
    after = operator_state()
    assert after == before, f"the operator's checkout changed:\n{before}\n---\n{after}"
  '';
}
