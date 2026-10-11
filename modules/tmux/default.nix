{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.tmux.enable {
    "environment" = {
      "systemPackages" = [ pkgs.tmux ];
    };
  };
  options."myConfig"."modules"."tmux"."enable" = lib.mkEnableOption "tmux terminal multiplexer";
}
