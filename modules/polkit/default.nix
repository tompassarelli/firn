{ config, lib, ... }:
let
  cfg = config.myConfig.modules.polkit;
in
{
  options.myConfig.modules.polkit.enable = lib.mkEnableOption "Polkit security configuration";
  config = lib.mkIf cfg.enable { security.polkit.enable = true; };
}
