{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.vim;
in
{
  options.myConfig.modules.vim.enable = lib.mkEnableOption "Vim text editor";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.vim ]; };
}
