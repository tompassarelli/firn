{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.glow.enable {
    "environment" = {
      "systemPackages" = [ pkgs.glow ];
    };
  };
  options."myConfig"."modules"."glow"."enable" = lib.mkEnableOption "glow — terminal markdown renderer (tables, pager, dir browser)";
}
