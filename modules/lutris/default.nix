{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.lutris;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.lutris ]; };
  options.myConfig.modules.lutris.enable = lib.mkEnableOption "Lutris gaming platform";
}
