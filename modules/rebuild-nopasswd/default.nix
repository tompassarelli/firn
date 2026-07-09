{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.rebuild-nopasswd.enable = lib.mkEnableOption "Passwordless sudo for nixos-rebuild (agent-autonomous firn rebuild)";
  config = lib.mkIf config.myConfig.modules.rebuild-nopasswd.enable {
    security.sudo.extraRules = [
      {
        users = [ "tom" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/nixos-rebuild";
            options = [ "NOPASSWD" "SETENV" ];
          }
        ];
      }
    ];
  };
}
