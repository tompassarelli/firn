{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.agent-user;
  operator = config.myConfig.modules.users.username;
  operatorGroups = lib.attrByPath [ operator "extraGroups" ] [ ] config.users.users;
  operatorGroup = lib.attrByPath [ operator "group" ] "" config.users.users;
  loginShell = pkgs.writeTextFile {
    name = "agent-login-shell";
    executable = true;
    destination = "/bin/agent-login-shell";
    text = ''
      #!${pkgs.dash}/bin/dash
      if [ "$#" -eq 2 ] && [ "$1" = -c ]; then
        exec ${pkgs.coreutils}/bin/env -u BASH_ENV -u ENV ${pkgs.bashInteractive}/bin/bash --norc --noprofile -c '. /etc/profile; PATH=/run/wrappers/bin:/run/current-system/sw/bin:/var/lib/agent-runtime/current; eval "$1"' bash "$2"
      fi
      exec ${pkgs.bashInteractive}/bin/bash -l "$@"
    '';
    passthru.shellPath = "/bin/agent-login-shell";
  };
in
{
  imports = [ ./starts.nix ];
  options.myConfig.modules.agent-user = {
    enable = lib.mkEnableOption "the agent Unix user that runs every agent session on this host: its own home, no supplementary groups, and no membership of the operator's account";
    name = lib.mkOption {
      type = lib.types.str;
      default = "agent";
      description = "Unix user and primary group of the agent sessions";
    };
    home = lib.mkOption {
      type = lib.types.str;
      default = "/home/agent";
      description = "Home of the agent user, mode 0700 so no other account reads it";
    };
    gid = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = "Numeric group ID of the agent group, pinned so the broker can grant its socket by number";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.etc."north/operator".text = operator;
    environment.systemPackages = [ pkgs.git ];
    services.openssh.extraConfig = lib.mkIf config.services.openssh.enable (
      lib.mkAfter ''
        Match User ${cfg.name}
          PermitUserRC no
      ''
    );
    users.groups.${cfg.name} = {
      inherit (cfg) gid;
    };
    users.users.${cfg.name} = {
      isNormalUser = true;
      group = cfg.name;
      extraGroups = [ ];
      inherit (cfg) home;
      createHome = true;
      homeMode = "0700";
      linger = true;
      shell = loginShell;
      hashedPassword = "!";
      description = "north agent sessions";
    };
    assertions = [
      {
        assertion =
          !(lib.elem cfg.name operatorGroups)
          && operatorGroup != cfg.name
          && !(lib.elem operator config.users.groups.${cfg.name}.members);
        message = "the operator's account must not join the agent group ${cfg.name}, or the agent's files would be the operator's to reach";
      }
      {
        assertion = !(lib.elem cfg.name config.nix.settings.trusted-users);
        message = "the agent user ${cfg.name} must not be a Nix trusted user, since a trusted user can make the daemon run any store path it names";
      }
      {
        assertion = config.users.users.${cfg.name}.extraGroups == [ ];
        message = "the agent user ${cfg.name} takes no supplementary group; a group such as wheel, input or docker hands it that group's power";
      }
      {
        assertion =
          !(lib.any (group: lib.elem cfg.name group.members) (lib.attrValues config.users.groups));
        message = "the agent user ${cfg.name} must be a member of no group but its own primary group";
      }
    ];
  };
}
