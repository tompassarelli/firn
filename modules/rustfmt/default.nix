{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.rustfmt.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.rustfmt ];
    };
  };
  options."myConfig"."modules"."rustfmt"."enable" = lib.mkEnableOption "Rust formatter";
}
