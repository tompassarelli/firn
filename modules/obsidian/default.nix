{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.obsidian;
in
{
  options.myConfig.modules.obsidian.enable = lib.mkEnableOption "Obsidian note-taking";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.obsidian ]; };
}
