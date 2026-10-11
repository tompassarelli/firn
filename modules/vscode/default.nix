{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.vscode.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.vscode ];
    };
  };
  options."myConfig"."modules"."vscode"."enable" = lib.mkEnableOption "Visual Studio Code (Microsoft build)";
}
