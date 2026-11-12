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
  relative = to: lib.removePrefix "${agent.home}/" to;
  parents =
    to:
    lib.tail (
      lib.scanl (dir: part: "${dir}/${part}") agent.home (lib.init (lib.splitString "/" (relative to)))
    );
  copy =
    from: to:
    let
      q = lib.escapeShellArg;
      owner = "${agent.name}:${agent.name}";
    in
    ''
      if [ -e ${q from} ] && [ ! -e ${q to} ]; then
        ${
          lib.concatMapStrings (dir: "install -d -o ${agent.name} -g ${agent.name} ${q dir}\n") (parents to)
        }cp -a --reflink=auto ${q from} ${q to}
        chown -R ${owner} ${q to}
      fi
    '';
in
{
  options.myConfig.modules.agent-cache-seed = {
    enable = lib.mkEnableOption "a one-time copy of the operator's caches into the agent user's home, owned by the agent user afterwards";
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
      description = "Copy the operator's caches into the agent user's home once, then own them as the agent user";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      unitConfig.ConditionPathExists = "!${stamp}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "agent-cache-seed" ''
          set -eu
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList copy cfg.sources)}
          touch ${stamp}
        '';
      };
    };
  };
}
