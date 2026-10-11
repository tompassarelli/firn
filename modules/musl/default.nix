{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.musl.enable {
    "environment" = {
      "systemPackages" = [ pkgs.musl.dev ];
    };
  };
  options."myConfig"."modules"."musl"."enable" = lib.mkEnableOption "musl C compiler toolchain";
}
