{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.shellcheck;
in
{
  options.myConfig.modules.shellcheck.enable = lib.mkEnableOption "ShellCheck shell script linter";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.shellcheck ]; };
}
