{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.agent-cache-seed;
  agent = config.myConfig.modules.agent-user;
  stamp = "/var/lib/agent-user/caches-seeded";
  pairs = lib.concatMap (from: [
    (lib.escapeShellArg from)
    (lib.escapeShellArg cfg.sources.${from})
  ]) (lib.attrNames cfg.sources);
in
{
  options.myConfig.modules.agent-cache-seed = {
    enable = lib.mkEnableOption "a one-time copy of the operator's caches into the agent user's home, made by the agent user itself so no root process writes or chowns under that home";
    sources = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "/home/operator/.cargo/registry" = "/home/agent/.cargo/registry";
      };
      description = "Operator cache paths to copy, each mapped to its destination under the agent user's home; copied once, behind a stamp only root writes";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = agent.enable;
        message = "agent-cache-seed seeds the agent user's home, so myConfig.modules.agent-user must be enabled";
      }
      {
        assertion = lib.all (to: lib.hasPrefix "${agent.home}/" to) (lib.attrValues cfg.sources);
        message = "every agent-cache-seed destination must lie under ${agent.home}";
      }
    ];
    systemd.tmpfiles.rules = [ "d /var/lib/agent-user 0700 root root -" ];
    systemd.services.agent-cache-seed = {
      description = "Copy the operator's caches into the agent user's home once, as the agent user";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      unitConfig.ConditionPathExists = "!${stamp}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "agent-cache-seed" ''
          set -eu
          ${pkgs.util-linux}/bin/runuser -u ${agent.name} -- ${pkgs.coreutils}/bin/env PATH=${
            lib.makeBinPath [ pkgs.coreutils ]
          } ${pkgs.bash}/bin/bash ${./copy.sh} ${lib.escapeShellArg agent.home} ${lib.concatStringsSep " " pairs}
          touch ${stamp}
        '';
      };
    };
  };
}
