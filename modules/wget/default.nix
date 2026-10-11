{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.wget.enable {
    "environment" = {
      "systemPackages" = [ pkgs.wget ];
    };
  };
  options."myConfig"."modules"."wget"."enable" = lib.mkEnableOption "wget download tool";
}
