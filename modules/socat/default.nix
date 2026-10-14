{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.socat;
in
{
  options.myConfig.modules.socat.enable = lib.mkEnableOption "socat";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.socat ]; };
}
