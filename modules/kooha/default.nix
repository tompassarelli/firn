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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.kooha ]; };
  options.myConfig.modules.kooha.enable = lib.mkEnableOption "Kooha screen recorder";
}
