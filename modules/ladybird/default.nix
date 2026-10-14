{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.ladybird;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.ladybird ]; };
  options.myConfig.modules.ladybird.enable =
    lib.mkEnableOption "Enable Ladybird browser (bleeding edge from git)";
}
