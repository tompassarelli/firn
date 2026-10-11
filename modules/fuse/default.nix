{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.fuse.enable {
    "environment" = {
      "systemPackages" = [ pkgs.fuse ];
    };
  };
  options."myConfig"."modules"."fuse"."enable" = lib.mkEnableOption "FUSE filesystem support";
}
