{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.dotnet;
in
{
  config = lib.mkIf cfg.enable {
    environment = {
      sessionVariables.PATH = [ "$HOME/.dotnet/tools" ];
      systemPackages = [ pkgs.dotnet-sdk_8 ];
    };
  };
  options.myConfig.modules.dotnet.enable = lib.mkEnableOption ".NET SDK and CLI tools";
}
