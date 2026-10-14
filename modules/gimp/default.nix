{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gimp;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gimp ]; };
  options.myConfig.modules.gimp.enable = lib.mkEnableOption "GIMP image editor";
}
