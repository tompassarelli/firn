{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.auto-upgrade.enable = lib.mkEnableOption "Automatic system updates";
  config = lib.mkIf config.myConfig.modules.auto-upgrade.enable {
    system.autoUpgrade = {
      enable = true;
      flake = "${config.myConfig.modules.users.codeDir}/nixos-config";
      flags = [
        "--update-input"
        "nixpkgs"
        "--update-input"
        "nixpkgs-unstable"
        "--commit-lock-file"
      ];
      dates = "Sun 03:00";
      randomizedDelaySec = "30min";
      allowReboot = false;
    };
  };
}
