{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.protonup-qt;
in
{
  options.myConfig.modules.protonup-qt.enable =
    lib.mkEnableOption "ProtonUp-Qt compatibility tool manager";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ protonup-qt ];
  };
}
