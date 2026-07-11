{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.river.enable = lib.mkEnableOption "Enable river 0.4 Wayland compositor (pluggable-WM lane; opt-in)";
  config = lib.mkIf config.myConfig.modules.river.enable {
    programs.river.enable = true;
    programs.river.package = pkgs.unstable.river;
    programs.river.xwayland.enable = true;
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };
}
