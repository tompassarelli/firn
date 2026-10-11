{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gitleaks.enable {
    "environment" = {
      "systemPackages" = [ pkgs.gitleaks ];
    };
  };
  options."myConfig"."modules"."gitleaks"."enable" = lib.mkEnableOption "Enable gitleaks secret scanner (safe-push depends on it being on PATH)";
}
