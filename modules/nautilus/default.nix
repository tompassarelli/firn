{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.nautilus;
in
{
  options.myConfig.modules.nautilus.enable = lib.mkEnableOption "Nautilus file manager";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.nautilus ];
    services.gvfs.enable = true;
  };
}
