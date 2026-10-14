{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.kooha;
in
{
  options.myConfig.modules.kooha.enable = lib.mkEnableOption "Kooha screen recorder";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.kooha ]; };
}
