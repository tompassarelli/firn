{
  pkgs,
  guarded ? true,
}:

let
  keys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  plant = pkgs.writeShellScript "plant-login-reads" ''
    set -eu
    for rc in .bashrc .bash_profile .bash_login .profile; do
      printf 'echo login-rc-marker\nexport BASH_ENV="$HOME/env.sh"\nhead() { echo /home/agent/planted-function; }\nexport PATH="$HOME/.nix-profile/bin:$PATH"\n' >>"$HOME/$rc"
    done
    printf 'echo login-rc-marker\n' >"$HOME/env.sh"
    mkdir -p "$HOME/.ssh" "$HOME/.nix-profile/bin"
    printf 'echo login-rc-marker\n' >"$HOME/.ssh/rc"
    printf '#!/bin/sh\necho /home/agent/planted\n' >"$HOME/.nix-profile/bin/head"
    chmod +x "$HOME/.nix-profile/bin/head"
  '';
in
pkgs.testers.runNixOSTest {
  name = "agent-login-reads${if guarded then "" else "-unguarded"}";

  nodes.vm =
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
        users.users.operator.isNormalUser = true;
        users.users.agent = {
          openssh.authorizedKeys.keys = [ keys.snakeOilPublicKey ];
          shell = lib.mkIf (!guarded) (lib.mkForce pkgs.bashInteractive);
        };
        services.openssh = {
          enable = true;
          extraConfig = lib.mkBefore "AcceptEnv BASH_ENV ENV";
        };
      };
    };

  testScript = ''
    import shlex

    vm.start()
    vm.wait_for_unit("sshd.service")
    vm.succeed("install -D -m 0600 ${keys.snakeOilPrivateKey} /root/.ssh/id")
    vm.succeed("runuser -u agent -- ${plant}")

    def login(command):
        return vm.succeed(
            "ssh -i /root/.ssh/id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
            " -o SetEnv='BASH_ENV=/home/agent/env.sh ENV=/home/agent/env.sh'"
            f" agent@vm -- {shlex.quote(command)} 2>&1"
        )

    quiet = login("true")
    assert "login-rc-marker" not in quiet, f"ssh agent@vm -- true ran a file the agent can write:\n{quiet}"

    probed = login("head -n 1 /etc/north/operator")
    assert probed == "operator", f"a bare head over the agent login ran a copy the agent can write:\n{probed}"
  '';
}
