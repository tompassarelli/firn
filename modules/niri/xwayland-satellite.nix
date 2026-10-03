{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.niri.enable {
    environment.systemPackages = [ pkgs.unstable.xwayland-satellite ];
  };
}
