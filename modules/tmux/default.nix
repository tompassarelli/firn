{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.tmux;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.tmux ]; };
  options.myConfig.modules.tmux.enable = lib.mkEnableOption "tmux terminal multiplexer";
}
