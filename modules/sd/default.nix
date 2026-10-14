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
  options.myConfig.modules.sd.enable = lib.mkEnableOption "sd find-and-replace tool";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sd ]; };
}
