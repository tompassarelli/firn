{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.bitwarden-cli;
in
{
  options.myConfig.modules.bitwarden-cli.enable = lib.mkEnableOption "bw — Bitwarden vault CLI";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.bitwarden-cli ]; };
}
