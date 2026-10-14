{ config, lib, ... }:
let
  cfg = config.myConfig.modules.rebuild-nopasswd;
in
{
  config = lib.mkIf cfg.enable { security.sudo.wheelNeedsPassword = false; };
  options.myConfig.modules.rebuild-nopasswd.enable =
    lib.mkEnableOption "Passwordless sudo for nixos-rebuild (agent-autonomous firn rebuild)";
}
