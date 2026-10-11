{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.piper.enable {
    "environment" = {
      "systemPackages" = [ pkgs.piper ];
    };
    "services" = {
      "ratbagd" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."piper"."enable" = lib.mkEnableOption "gaming mouse configuration (Piper + ratbagd)";
}
