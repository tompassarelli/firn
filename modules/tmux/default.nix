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
  options.myConfig.modules.tmux.enable = lib.mkEnableOption "tmux terminal multiplexer";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.tmux ]; };
}
