{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.azure-cli;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.azure-cli ]; };
  options.myConfig.modules.azure-cli.enable =
    lib.mkEnableOption "Azure CLI (az) for Entra / Microsoft Graph admin";
}
