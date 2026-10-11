{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gcc.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gcc ];
    };
  };
  options."myConfig"."modules"."gcc"."enable" = lib.mkEnableOption "GNU C compiler";
}
