{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.agent-runtime-link;
  operator = config.myConfig.modules.users.username;
  directory = builtins.dirOf cfg.path;
in
{
  options.myConfig.modules.agent-runtime-link = {
    enable = lib.mkEnableOption "the runtime link the agent user follows: a symlink the operator's account owns in a directory only it writes, so the agent reads the runtime and cannot repoint it";
    path = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/agent-runtime/current";
      description = "Where the link sits; its directory is owned by the operator's account, mode 0755";
    };
    target = lib.mkOption {
      type = lib.types.str;
      description = "Runtime directory the link points at, one the agent user can read";
    };
  };
  config = lib.mkIf cfg.enable {
    system.activationScripts.agent-runtime-link = {
      deps = [ "users" ];
      text = ''
        ${pkgs.coreutils}/bin/install -d -o ${operator} -m 0755 ${directory}
        ${pkgs.coreutils}/bin/ln -sfn -- ${cfg.target} ${cfg.path}
        ${pkgs.coreutils}/bin/chown -h ${operator} ${cfg.path}
      '';
    };
  };
}
