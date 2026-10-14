{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.spotify;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.spotify ]; };
  options.myConfig.modules.spotify.enable = lib.mkEnableOption "Spotify TUI player";
}
