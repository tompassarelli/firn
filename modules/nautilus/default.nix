{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.nautilus.enable = lib.mkEnableOption "Nautilus file manager";
  config = lib.mkIf config.myConfig.modules.nautilus.enable {
    environment.systemPackages = with pkgs; [ nautilus ];
    services.gvfs.enable = true;
  };
}
