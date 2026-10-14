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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.vim ]; };
  options.myConfig.modules.vim.enable = lib.mkEnableOption "Vim text editor";
}
