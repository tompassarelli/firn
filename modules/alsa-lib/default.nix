{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.alsa-lib.enable = lib.mkEnableOption "alsa-lib";
  config = lib.mkIf config.myConfig.modules.alsa-lib.enable {
    environment.systemPackages = [ pkgs.alsa-lib ];
  };
}
