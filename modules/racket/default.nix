{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.racket.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.racket ];
    };
  };
  options."myConfig"."modules"."racket"."enable" = lib.mkEnableOption "Racket programming language";
}
