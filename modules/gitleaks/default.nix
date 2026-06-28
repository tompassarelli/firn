{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.gitleaks.enable = lib.mkEnableOption "Enable gitleaks secret scanner (safe-push depends on it being on PATH)";
  config = lib.mkIf config.myConfig.modules.gitleaks.enable {
    environment.systemPackages = with pkgs; [ gitleaks ];
  };
}
