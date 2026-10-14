{ config, lib, ... }:
let
  cfg = config.myConfig.modules.polkit;
in
{
  config = lib.mkIf cfg.enable { security.polkit.enable = true; };
  options.myConfig.modules.polkit.enable = lib.mkEnableOption "Polkit security configuration";
}
