{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.vscode;
in
{
  options.myConfig.modules.vscode.enable = lib.mkEnableOption "Visual Studio Code (Microsoft build)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.vscode ]; };
}
