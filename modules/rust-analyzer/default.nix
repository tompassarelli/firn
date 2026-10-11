{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.rust-analyzer.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.rust-analyzer ];
    };
  };
  options."myConfig"."modules"."rust-analyzer"."enable" = lib.mkEnableOption "Rust language server";
}
