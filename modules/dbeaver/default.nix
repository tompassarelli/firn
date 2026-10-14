{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.dbeaver;
in
{
  options.myConfig.modules.dbeaver.enable = lib.mkEnableOption "DBeaver database GUI";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.dbeaver-bin ]; };
}
