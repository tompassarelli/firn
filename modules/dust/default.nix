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
  options.myConfig.modules.dust.enable = lib.mkEnableOption "dust";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.dust ]; };
}
