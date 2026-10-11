{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.bubblewrap.enable {
    "environment" = {
      "systemPackages" = [ pkgs.bubblewrap ];
    };
  };
  options."myConfig"."modules"."bubblewrap"."enable" = lib.mkEnableOption "Enable bubblewrap sandbox (north readonly-shell requires bwrap)";
}
