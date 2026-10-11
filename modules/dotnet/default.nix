{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.dotnet.enable {
    "environment" = {
      "sessionVariables" = {
        "PATH" = [ "$HOME/.dotnet/tools" ];
      };
      "systemPackages" = [ pkgs.dotnet-sdk_8 ];
    };
  };
  options."myConfig"."modules"."dotnet"."enable" = lib.mkEnableOption ".NET SDK and CLI tools";
}
