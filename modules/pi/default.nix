{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.pi;
in
{
  options.myConfig.modules.pi.enable =
    lib.mkEnableOption "pi terminal coding agent (MIT, badlogic/pi-mono via nixpkgs-unstable)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.pi-coding-agent ]; };
}
