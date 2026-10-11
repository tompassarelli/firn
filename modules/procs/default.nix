{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.procs.enable {
    "environment" = {
      "systemPackages" = [ pkgs.procs ];
    };
  };
  options."myConfig"."modules"."procs"."enable" = lib.mkEnableOption "Enable procs (modern ps replacement)";
}
