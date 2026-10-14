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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.shellcheck ]; };
  options.myConfig.modules.shellcheck.enable = lib.mkEnableOption "ShellCheck shell script linter";
}
