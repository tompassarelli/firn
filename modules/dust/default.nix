{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.dust;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.dust ]; };
  options.myConfig.modules.dust.enable = lib.mkEnableOption "dust";
}
