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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.obsidian ]; };
  options.myConfig.modules.obsidian.enable = lib.mkEnableOption "Obsidian note-taking";
}
