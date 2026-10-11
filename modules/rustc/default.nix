{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.rustc.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.rustc ];
    };
  };
  options."myConfig"."modules"."rustc"."enable" = lib.mkEnableOption "Rust compiler";
}
