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
  options.myConfig.modules.spotify.enable = lib.mkEnableOption "Spotify TUI player";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.spotify ]; };
}
