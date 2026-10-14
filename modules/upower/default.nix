{ config, lib, ... }:
let
  cfg = config.myConfig.modules.upower;
in
{
  config = lib.mkIf cfg.enable { services.upower.enable = true; };
  options.myConfig.modules.upower.enable = lib.mkEnableOption "UPower power management";
}
