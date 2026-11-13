{
  pkgs,
  fill,
  design ? "agent-owned",
}:

let
  operatorHome = "/home/operator";
  checkoutOf =
    {
      agent-owned = "\"$HOME/$1\"";
      operator-checkout = "${operatorHome}/$1";
    }
    .${design};
  remote = pkgs.writeShellScript "offloaded-check" ''
    set -eu
    PATH="$HOME/.local/bin:$PATH"
    . ${fill}
    repo=${checkoutOf} base=$2 head=$3 name=$4 ref=refs/heads/$5
    root=$HOME/.cache/land-offload
    mkdir -p "$root"
    bundle=$(mktemp "$root/$name.bundle.XXXXXX")
    trap 'rm -f "$bundle"; git -C "$repo" update-ref -d "$ref" 2>/dev/null || true' EXIT
    cat >"$bundle"
    fill
    slot=$root/$name
    place
    cd "$slot"
    if confined_here; then confine sh ./check.sh; else sh ./check.sh; fi
  '';
  bundleFor = pkgs.writeShellScript "lane-bundle" ''
    set -eu
    cd ${operatorHome}/code/"$1"/main
    branch=$2
    shift 2
    cuts=
    for commit in "$@"; do cuts="$cuts ^$commit"; done
    git bundle create -q - refs/heads/"$branch" $cuts
  '';
  check = pkgs.writeText "check.sh" ''
    echo "uid $(id -u)"
    echo "dir $(pwd)"
    test "$(cat answer)" = 42
  '';
  plantingCheck = pkgs.writeText "planting-check.sh" ''
    echo "uid $(id -u)"
    echo "dir $(pwd)"
    test "$(cat answer)" = 42
    common=$(git rev-parse --path-format=absolute --git-common-dir)
    plant() {
      name=$1
      shift
      if "$@" 2>/dev/null; then echo "planted $name"; else echo "refused $name"; fi
    }
    hooks() {
      for hook in post-checkout reference-transaction; do
        printf '#!/bin/sh\ntouch "$HOME/hook-ran"\n' >"$common/hooks/$hook" && chmod +x "$common/hooks/$hook" || return 1
      done
    }
    objects() {
      find "$common/objects" -type f | while read -r object; do printf x >>"$object" || exit 1; done
    }
    plant hooks hooks
    plant object objects
    plant config git config filter.evil.smudge 'touch "$HOME/filter-ran"; cat'
    plant attributes sh -c 'printf "* filter=evil diff=evil\n" >>"$0/info/attributes"' "$common"
    plant global-config git config --global filter.evil.smudge 'touch "$HOME/filter-ran"; cat'
    plant global-attributes sh -c 'printf "* filter=evil\n" >>"$HOME/.config/git/attributes"'
    plant local-bin sh -c 'mkdir -p "$HOME/.local/bin" && printf "#!/bin/sh\ntouch \"\$HOME/git-ran\"\nexec /run/current-system/sw/bin/git \"\$@\"\n" >"$HOME/.local/bin/git" && chmod +x "$HOME/.local/bin/git"'
    plant shell-rc sh -c 'printf "touch \"\$HOME/rc-ran\"\n" >>"$HOME/.bashrc" && printf "touch \"\$HOME/rc-ran\"\n" >>"$HOME/.profile"'
    plant authorized-keys sh -c 'mkdir -p "$HOME/.ssh" && echo "ssh-ed25519 AAAAplanted lane" >>"$HOME/.ssh/authorized_keys"'
    plant slot-gitdir sh -c 'mkdir -p evil && printf "gitdir: %s/evil\n" "$PWD" >.git'
    plant commondir sh -c 'printf "%s/evil\n" "$PWD" >"$(git rev-parse --absolute-git-dir)/commondir"'
    touch planted
  '';
  plantedCheck = pkgs.writeText "planted-check.sh" ''
    echo "uid $(id -u)"
    echo "dir $(pwd)"
    test "$(cat answer)" = 42
    test ! -e planted || { echo "lane B sees the untracked file lane A left"; exit 1; }
    test ! -e "$HOME/hook-ran" || { echo "a hook lane A planted ran in lane B's offload"; exit 1; }
    test ! -e "$HOME/filter-ran" || { echo "a filter driver lane A planted ran in lane B's offload"; exit 1; }
    test ! -e "$HOME/git-ran" || { echo "a git lane A planted in the agent's home ran in lane B's offload"; exit 1; }
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
        environment.systemPackages = [
          pkgs.git
          pkgs.bubblewrap
        ];
        programs.git = {
          enable = true;
          config = {
            user = {
              name = "fixture";
              email = "fixture@example.invalid";
            };
            safe.directory = "/srv/public/proj.git";
          };
        };
      };
    };

  testScript = ''
    import shlex


    def operator(command):
        return host.succeed(f"runuser -l operator -c {shlex.quote(command)}").strip()


    def agent(command):
        return host.succeed(f"runuser -l agent -c {shlex.quote(command)}").strip()


    def checkout(project):
        return f"${operatorHome}/code/{project}/main"


    def offload(project, branch, base, head, cuts):
        bundle = f"runuser -l operator -c {shlex.quote(f'${bundleFor} {project} {branch} ' + ' '.join(cuts))}"
        check = f"runuser -l agent -c {shlex.quote(f'${remote} code/{project}/main {base} {head} {project}-lane {branch}')}"
        status, output = host.execute(f"{bundle} | {check} 2>&1")
        print(f"the offloaded check of {project} {branch} cut at {cuts} exited {status}:\n{output}")
        return status, output


    def held(project):
        tips = agent(f"git -C ~/code/{project}/main for-each-ref --format='%(objectname)'").split()
        known = operator(
            f"printf '%s\\n' {' '.join(tips)} | git -C {checkout(project)} cat-file --batch-check='%(objectname) %(objecttype)'"
        ) if tips else ""
        return [line.split()[0] for line in known.splitlines() if line.endswith(" commit")]


    def shipped(project, branch, base, head):
        status, output = offload(project, branch, base, head, [base])
        if status == 97:
            status, output = offload(project, branch, base, head, held(project))
        ran = dict(line.split(" ", 1) for line in output.splitlines() if line.startswith(("uid ", "dir ")))
        assert status == 0, f"the offloaded check of {project} {branch} failed as the agent:\n{output}"
        assert ran.get("uid") == agent_uid, f"the check ran as uid {ran.get('uid')}, not the agent's {agent_uid}"
        assert ran.get("dir", "").startswith("/home/agent/"), f"the check ran in {ran.get('dir')}, outside the agent's home"
        return output


    def operator_state():
        return operator(
            "for c in ~/code/*/main; do git -C $c rev-parse HEAD && git -C $c --no-optional-locks status --porcelain"
            " && find $c -printf '%p %T@ %m %u\\n' | sort; done"
        )


    def commit(project, message, files):
        steps = " && ".join(f"{source} > {name}" for name, source in files.items())
        operator(f"cd {checkout(project)} && {steps} && git add -A && git commit -q -m {message}")
        return operator(f"git -C {checkout(project)} rev-parse HEAD")


    host.start()
    host.wait_for_unit("multi-user.target")
    agent_uid = host.succeed("id -u agent").strip()

    host.succeed(
        "install -d -o operator -g users -m 0755 /srv/public",
        "install -d -o operator -g users -m 0700 /srv/private",
    )
    for project, forge in [("proj", "/srv/public/proj.git"), ("vault", "/srv/private/vault.git")]:
        operator(
            f"git init -q --bare -b main {forge} && mkdir -p {checkout(project)} && chmod 0700 ~/code ~/code/{project} {checkout(project)}"
            f" && cd {checkout(project)} && git init -q -b main && git remote add origin {forge}"
        )
    host.succeed("test \"$(stat -c '%a' ${operatorHome})\" = 700")

    commit("proj", "old", {"check.sh": "cat ${check}", "answer": "echo 40"})
    operator(f"git -C {checkout('proj')} push -q origin main")
    agent("mkdir -p ~/code/proj && git clone -q /srv/public/proj.git ~/code/proj/main")
    base = commit("proj", "base", {"answer": "echo 41"})
    operator(f"git -C {checkout('proj')} push -q origin main && git -C {checkout('proj')} checkout -q -b lane")
    lane = commit("proj", "lane", {"check.sh": "cat ${plantingCheck}", "answer": "echo 42"})
    operator(f"git -C {checkout('proj')} checkout -q -b next")
    following = commit("proj", "next", {"check.sh": "cat ${plantedCheck}"})
    operator(f"git -C {checkout('proj')} checkout -q main")

    vbase = commit("vault", "base", {"check.sh": "cat ${check}", "answer": "echo 41"})
    operator(f"git -C {checkout('vault')} push -q origin main && git -C {checkout('vault')} checkout -q -b lane")
    vlane = commit("vault", "lane", {"answer": "echo 42"})
    operator(f"git -C {checkout('vault')} checkout -q main")
    vbase2 = commit("vault", "base2", {"note": "echo second"})
    operator(f"git -C {checkout('vault')} push -q origin main && git -C {checkout('vault')} checkout -q -b lane2")
    vlane2 = commit("vault", "lane2", {"answer": "echo 42"})
    operator(f"git -C {checkout('vault')} checkout -q main")
    agent("mkdir -p ~/code/vault && git init -q -b main ~/code/vault/main")

    host.fail(
        "runuser -l agent -c 'ls ${operatorHome}'",
        f"runuser -l agent -c 'cat {checkout('proj')}/check.sh'",
        f"runuser -l agent -c 'git -C {checkout('proj')} cat-file -e {base}'",
        "runuser -l agent -c 'ls /srv/private'",
        f"runuser -l agent -c 'git -C ~/code/proj/main cat-file -e {base}'",
    )
    before = operator_state()

    planting = shipped("proj", "lane", base, lane)
    for store in ["hooks", "object", "config", "attributes", "global-config", "global-attributes", "local-bin", "shell-rc", "authorized-keys", "slot-gitdir", "commondir"]:
        assert f"refused {store}" in planting, f"lane A's check could write the shared {store}:\n{planting}"
    shipped("proj", "next", lane, following)
    host.succeed("test ! -e ~agent/hook-ran", "test ! -e ~agent/filter-ran", "test ! -e ~agent/git-ran", "test ! -e ~agent/rc-ran", "test ! -e ~agent/.ssh/authorized_keys")

    shipped("vault", "lane", vbase, vlane)
    assert held("vault") == [vlane], f"the agent's vault checkout holds {held('vault')}, not the lane it was shipped"
    shipped("vault", "lane2", vbase2, vlane2)

    host.succeed(
        "test \"$(stat -c '%U %a' /home/agent)\" = 'agent 700'",
        "test -z \"$(find /home/agent -not -user agent -print)\"",
    )
    after = operator_state()
    assert after == before, f"the operator's checkouts changed:\n{before}\n---\n{after}"
  '';
}
