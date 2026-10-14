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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.dbeaver-bin ]; };
  options.myConfig.modules.dbeaver.enable = lib.mkEnableOption "DBeaver database GUI";
}
