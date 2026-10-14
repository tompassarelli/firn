{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sd;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sd ]; };
  options.myConfig.modules.sd.enable = lib.mkEnableOption "sd find-and-replace tool";
}
