{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.shellcheck.enable {
    "environment" = {
      "systemPackages" = [ pkgs.shellcheck ];
    };
  };
  options."myConfig"."modules"."shellcheck"."enable" = lib.mkEnableOption "ShellCheck shell script linter";
}
