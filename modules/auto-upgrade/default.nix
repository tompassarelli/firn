{ config, lib, ... }:
let
  cfg = config.myConfig.modules.auto-upgrade;
in
{
  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      allowReboot = false;
      dates = "Sun 03:00";
      enable = true;
      flags = [
        "--update-input"
        "nixpkgs"
        "--update-input"
        "nixpkgs-unstable"
        "--commit-lock-file"
      ];
      flake = "${config.myConfig.modules.users.codeDir}/nixos-config";
      randomizedDelaySec = "30min";
    };
  };
  options.myConfig.modules.auto-upgrade.enable = lib.mkEnableOption "Automatic system updates";
}
