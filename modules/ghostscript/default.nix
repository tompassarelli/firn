{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.ghostscript.enable {
    "environment" = {
      "systemPackages" = [ pkgs.ghostscript ];
    };
  };
  options."myConfig"."modules"."ghostscript"."enable" = lib.mkEnableOption "Ghostscript PostScript interpreter";
}
