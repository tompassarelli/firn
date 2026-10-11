{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.clippy.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.clippy ];
    };
  };
  options."myConfig"."modules"."clippy"."enable" = lib.mkEnableOption "Rust linter";
}
