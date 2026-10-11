{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.cargo.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.cargo ];
    };
  };
  options."myConfig"."modules"."cargo"."enable" = lib.mkEnableOption "Rust package manager";
}
