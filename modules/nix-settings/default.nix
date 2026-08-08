{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.nix-settings.enable = lib.mkEnableOption "Nix configuration and package settings";
  config = lib.mkIf config.myConfig.modules.nix-settings.enable {
    nixpkgs.config.allowUnfree = true;
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      builders-use-substitutes = true;
      max-jobs = "auto";
      cores = 8;
      auto-optimise-store = true;
      keep-outputs = true;
      keep-derivations = true;
      trusted-users = [ "root" "@wheel" ];
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://walker.cachix.org"
        "https://walker-git.cachix.org"
        "https://devenv.cachix.org"
        "https://quickshell.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
        "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "quickshell.cachix.org-1:vBm3s5tZThc5KDLj6zhHVCMp8wX/AZJwle9wqdi81ts="
      ];
    };
    systemd.services.nix-daemon.serviceConfig.CPUWeight = 50;
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    boot.loader.systemd-boot.configurationLimit = 10;
  };
}
