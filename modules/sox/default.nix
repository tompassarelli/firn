{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sox;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sox ]; };
  options.myConfig.modules.sox.enable =
    lib.mkEnableOption "Enable SoX audio recording for Claude Code voice mode";
}
