{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.nheko;
in
{
  options.myConfig.modules.nheko.enable = lib.mkEnableOption "Nheko Matrix client";
  config = lib.mkIf cfg.enable {
    nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];
    environment.systemPackages = [ pkgs.nheko ];
  };
}
