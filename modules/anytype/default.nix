{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.anytype.enable {
    "environment" = {
      "systemPackages" = [ pkgs.anytype ];
    };
  };
  options."myConfig"."modules"."anytype"."enable" = lib.mkEnableOption "Anytype — local-first knowledge/notes workspace";
}
